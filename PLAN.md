# WinTab – plan

A window switcher for macOS that works like Alt+Tab on Windows: it cycles through **windows**, not apps
(the system ⌘Tab switches apps). No "Pro" upsells – that is the reason this exists next to
[AltTab](https://github.com/lwouis/alt-tab-macos) and DockDoor.

Target behaviour (all milestones done):

- `⌘ Tab` replaces the system app switcher (can be switched to `⌥ Tab` instead).
- Window previews (thumbnails), window title and app icon.
- Windows from **all Spaces**, including minimized windows, hidden apps and fullscreen windows.
- Most-recently-used (MRU) order.
- Keys: Tab / arrows = next, ⇧Tab = back, releasing the modifier = switch, Esc = cancel, mouse click = switch.
- Agent app (`LSUIElement`): no Dock icon, a menu bar icon with settings.

Update this file when a milestone is done or the plan changes – it is how the next session knows where to continue.

## Milestones

### 1. Usable base on ⌥Tab – current Space ✅ (2026-11-17)

- Agent app with a menu bar icon (About, Quit; "Grant Accessibility Permission…" while missing).
- Global hotkey `⌥ Tab` through a `CGEventTap` (`KeyboardTap`), key logic in `HotkeyStateMachine` (tested).
- Window list of the current Space: `kAXWindowsAttribute` of every regular app (title, subrole, minimized)
  matched to `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` (front-to-back order) via the private
  `_AXUIElementGetWindow` (fallback: same app + same frame). Order: visible windows front to back, then
  windows of hidden apps, then minimized windows (`WindowListBuilder`, tested).
- Overlay: non-activating `NSPanel` with a SwiftUI grid (app icon + window title) on the screen with the
  mouse pointer; it appears after 120 ms, so a quick ⌥Tab just flips to the previous window.
- Switching: un-minimize, unhide, `AXRaise`, `kAXMainAttribute`, app `kAXFrontmostAttribute` + `activate()`.
- Accessibility permission window that closes itself once the permission is granted.
- Stable local code signing ("WinTab Local Dev" certificate, `scripts/setup-dev-signing.sh`).

Known limits of milestone 1: windows on other Spaces are not listed; the order is the on-screen z-order
(which is MRU for visible windows, but not for minimized ones); a window of an app with several windows
can occasionally stay behind its sibling (public API only, see milestone 4).

### 2. Replace ⌘Tab + MRU order ✅ (2026-11-17)

- `⌘ Tab` is the default shortcut (`HotkeyConfig.commandTab`); menu bar → Shortcut switches between ⌘Tab
  and ⌥Tab (`ShortcutChoice`, stored in UserDefaults under `shortcut`).
- The system ⌘Tab / ⌘⇧Tab are turned off with the private `CGSSetSymbolicHotKeyEnabled` (hot keys 1 and 2;
  ⌘` = 6 stays with the system) – `SystemAppSwitcher` + `CommandTabGuard`. Verified: the off state is
  global and survives the process, so it is restored by `applicationWillTerminate`, by signal handlers
  (SIGTERM, SIGINT, crashes) and by a watchdog process `WinTab --watchdog <pid>` that waits for the main
  process to exit (also SIGKILL / force quit) – it skips the restore when another WinTab instance runs.
- While secure input is on (password fields, Terminal's Secure Keyboard Entry) event taps get no keys,
  so the system ⌘Tab is turned back on meanwhile (`IsSecureEventInputEnabled`, polled once a second).
- The permission is polled once a second; when it is revoked, the tap and focus tracking stop, the
  system ⌘Tab comes back and the permission window opens.
- MRU order: `RecentWindows` in WinTabCore (tested) – windows seen focused by recency, never-focused
  windows behind them in on-screen order, minimized windows last. `FocusTracker` feeds it from
  `NSWorkspace.didActivateApplicationNotification` and an `AXObserver` per app for
  `kAXFocusedWindowChangedNotification` (only when that app is frontmost). The focused window is also
  recorded right before listing, and the switched-to window after switching.
- When the focused window is not first in the list (e.g. the desktop is focused), forward selection starts
  on the first window instead of the second.
- The window list is read outside the event tap callback (any later key event loads it first if needed),
  with one `AXUIElementCopyMultipleAttributeValues` per window; ~30–40 ms warm with 13 windows, so no cache yet.

### 3. Window previews ✅ (2026-11-17)

- `ThumbnailStore` (Thumbnails.swift): `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly:
  true)` + `SCScreenshotManager.captureImage` with `SCContentFilter(desktopIndependentWindow:)`, at most
  480×300 px (`aspectFit`, tested), captured in parallel; ~110 ms for 11 windows including the content query.
- Cache per window ID: the switcher shows cached thumbnails at once and refreshes the listed visible windows
  when it opens; the window that loses the focus is captured too (so minimized / hidden windows keep a
  recent image – they can't be captured themselves). Entries of windows not listed for 30 min are dropped.
- Tiles: 232×196 pt with the thumbnail and the app icon as a badge; app icon until a thumbnail exists; icon
  tiles (milestone 1 look) when previews are off or not permitted. `GridLayout` (tested) balances rows and
  shrinks tiles down to 50 % when they don't fit 80 % of the screen height.
- Menu bar → "Window Previews" (UserDefaults `previews`, default on) and "Allow Screen Recording for
  Previews…" while the permission is missing. The system prompt (`CGRequestScreenCaptureAccess`) is shown
  once automatically (`askedForScreenRecording`), only after Accessibility is granted. The permission is
  polled with the rest of the state every second (`CGPreflightScreenCaptureAccess`).

### 4. All Spaces, minimized, fullscreen, precise focus (private APIs) ✅ (2026-11-17)

- All private calls live in `Sources/CPrivate` (C, looked up with `dlsym` at run time, so a macOS without
  them still launches – `WTPrivateAPIsAvailable()` reports it). Signatures, the key-window event record and
  the remote token format come from AltTab (GPL-3.0; credited in the C file, the header and the README).
- Windows of all Spaces: `CGSCopyManagedDisplaySpaces` (all Space IDs of all displays) →
  `CGSCopyWindowsWithOptionsAndTags` (window IDs, option 2) → public `CGWindowListCreateDescriptionFromArray`
  (pid, layer, bounds; the array must hold the raw window IDs, not CFNumbers) – `Spaces.windowsOnAllSpaces()`.
- Accessibility elements of windows on other Spaces (`kAXWindowsAttribute` only has the current Space and
  minimized windows): `RemoteWindowSearch` builds elements with `_AXUIElementCreateWithRemoteToken` for
  element IDs 0, 1, 2… on a background queue (200 ms budget per app, retried at most every 5 s, resumes
  where it stopped for the same windows), keeps only `AXWindow` roots and caches them per window ID. Found
  windows are listed from the next opening on; searches start at launch, on every Space change and when the
  switcher opens. Windows never found as AXWindow (toolbars / helper windows of fullscreen apps) stay out.
  Measured on macOS 27: Windows App's fullscreen window found in 6–17 ms.
- `WindowListBuilder.build(onScreen:otherSpaces:…)` (tested): order current Space → other Spaces → hidden
  apps → minimized, then MRU. `SwitcherWindow.isOnOtherSpace`.
- Precise focus: `WTFocusWindow` = `GetProcessForPID` + `_SLPSSetFrontProcessWithOptions(psn, wid,
  kCPSUserGenerated)` + two `SLPSPostEventRecordTo` records (key window), then `AXRaise`. Switches the Space
  when needed (also to fullscreen apps) and picks the exact window of multi-window apps. Falls back to the
  milestone 1 public-API path.
- Thumbnails of windows ScreenCaptureKit can't capture (fullscreen app on another Space) come from the private
  `CGSHWCaptureWindowList`, scaled down (`WTCopyWindowImage`).
- Menu bar → "Windows from All Desktops" (UserDefaults `allSpaces`, default on).
- Debugging: `WINTAB_SPACES=1` prints Spaces, windows on all Spaces and what the remote token search finds.

Not done / ideas: windows of hidden apps on other Spaces are not listed (they are ordered out and not in the
Space lists; AX only reports the current Space); a switcher that is already open is not refreshed when a
background search finds more windows; AltTab's newer `SLSWindowQueryWindows` batch API and WindowServer
notifications could replace polling-style refreshes.

### 5. Polish and release ✅ (2026-11-17)

- Settings window (menu bar → Settings…, ⌘,; `SettingsView` + `AppSettings` in UserDefaults): shortcut
  ⌘Tab / ⌥Tab, window previews, windows from all desktops, minimized windows, windows of hidden apps
  (`ListOptions` in WinTabCore, tested), excluded apps (by bundle ID, chosen with an open panel), switcher on
  the screen with the mouse pointer or the main screen, open at login, permissions with live state.
- Open at login: `SMAppService.mainApp` (`LoginItem`); "needs approval" links to System Settings → Login Items.
  It registers the bundle at its current path – re-enable it after moving WinTab.app (e.g. to /Applications).
- Permission onboarding (`PermissionsView`): shown when Accessibility is missing, and on the first launch when
  Screen Recording is missing; both rows with live state; closes by itself once everything is allowed.
- The menu bar menu is down to: status, Settings…, Permissions… (only while something is missing), About, Quit.
- Release prep: `CHANGELOG.md` has `## 0.1.0`; `scripts/release.sh 0.1.0` builds an ad-hoc signed universal
  app into `build/release/` (not over the development app) and `build/WinTab-0.1.0.zip`. Not published –
  creating the GitHub repository (assumed `Furcenzo/wintab` in `release.sh` / README) and
  `./scripts/release.sh 0.1.0 --publish` are up to the user.

App icon added afterwards: `scripts/make-icon.swift` → `Assets/AppIcon.icns` (three stacked windows on a blue
rounded square).

Ideas for later: refreshing an open switcher when the background search
finds more windows, hidden-app windows on other Spaces, WindowServer notifications instead of polling,
keyboard shortcuts inside the switcher (Q quit, W close, M minimize), a notarized release once there is an
Apple Developer ID (permissions would then survive updates).

### After 0.1.0

- #1: a click outside the switcher closes it (`NSEvent.addGlobalMonitorForEvents` for mouse-downs while it is
  open – a global monitor only sees other apps' events, i.e. clicks that are not on the panel).
- #2: × on the selected tile closes the window (`kAXCloseButtonAttribute` + `kAXPressAction`); with ⇧ held
  (`HotkeyStateMachine.isShiftHeld`) it turns red and force quits the app (`forceTerminate`). Tiles are removed
  with `Selection.remove(at:)` (tested) and the panel is resized.
- Homebrew: `brew install --cask furcenzo/tap/wintab`; the author's copy is adopted (`--adopt`) and replaced
  by a dev-signed build (`scripts/install-local.sh`). Development builds use the bundle ID
  `io.github.furcenzo.wintab.dev` ("WinTab Dev") so the login item can't pick them instead of /Applications.
- Menu bar icon "missing": on a notched MacBook macOS hides menu bar items that don't fit – not a WinTab bug.
  Reopening WinTab (Spotlight) shows Settings; `WINTAB_MENUBAR=all` lists the visible items.
- #3: README screenshots done (`Assets/screenshots/`, demo windows only, see CLAUDE.md); the showroom page on
  the author's website is still open (separate repository).

## Technical notes

- **Permissions are tied to the code signature.** TCC (Accessibility, Screen Recording) remembers an app by
  its designated requirement. Ad-hoc signed builds (`codesign --sign -`) have a new one on every build →
  the permission is lost every time. Development builds are therefore signed with a local self-signed
  certificate ("WinTab Local Dev", created once by `scripts/setup-dev-signing.sh`, approach from AltTab's
  `scripts/codesign/setup_local.sh`). Public releases stay ad-hoc signed, so users have to re-grant the
  permission after updating (until there is an Apple Developer ID).
- **Event tap:** `.cgSessionEventTap`, `.headInsertEventTap`, `.defaultTap` (may swallow events); needs the
  Accessibility permission. macOS disables a slow tap (`tapDisabledByTimeout`) – it is re-enabled; keep
  the callback fast. Secure input (password fields) hides keystrokes from all taps.
- **Activation on macOS 14+:** `NSRunningApplication.activate()` is "cooperative" and often refused for a
  background app; setting `kAXFrontmostAttribute` on the app element works for a trusted process.
- **SwiftUI overlay:** never look items up by index inside `ForEach` (`model.items[index]`) – SwiftUI may
  evaluate a row of the old list after the list changed, which crashed milestone 1 on closing the switcher.
  Pass the item values into the views.
- **Debugging without a keyboard/screen recording:** `WINTAB_LIST=1`, `WINTAB_SNAPSHOT=/x.png`
  (`WINTAB_VIEW=settings|permissions` renders those windows instead),
  `WINTAB_SWITCH=<n>`, `WINTAB_CYCLE=<n>` (open/close smoke test) – see `main.swift` / README. Crash
  reports: `~/Library/Logs/DiagnosticReports/WinTab-*.ips`.
- Milestones 1–5 were verified on macOS 27.0 (MacBook Air) by the user: listing, switching between
  windows of the same app, Tab / ⇧Tab / Esc / quick flip / mouse click / minimized windows, ⌘Tab replacing
  the system switcher, switching the shortcut in the menu, ⌘Tab back to the system after Quit, previews
(thumbnails, minimized windows, turning previews off) without noticeable delay, windows on other desktops
and a fullscreen app (listed, switched to the exact window), turning all desktops off, every setting in
the Settings window, excluded apps, open at login. The ⌘Tab
  restore after SIGKILL / SIGTERM / `pkill` was checked with `CGSIsSymbolicHotKeyEnabled`.
- **Logging:** `log stream --level debug --predicate 'subsystem == "io.github.furcenzo.wintab"'` shows focus
  changes, listed windows and thumbnail capture times.

## Risks

- Private APIs (SkyLight/CGS, `_AXUIElementGetWindow`, remote tokens) can break with any macOS release –
  keep them isolated in `CPrivate` with public fallbacks, test on every new macOS beta.
- Permissions are bound to the signature: every change of the signing identity (or a missing dev
  certificate) means granting Accessibility / Screen Recording again.
- macOS may periodically ask the user to confirm the Screen Recording permission again (monthly prompts
  since macOS 15) – previews must degrade gracefully to icons.
- Turning off the system ⌘Tab must always be undone (quit, crash, permission revoked), otherwise the user
  is left without any app switcher. Covered by the watchdog + signal handlers (milestone 2); if it ever
  stays off, starting and quitting WinTab, or logging out, brings it back.
- Not possible in the Mac App Store: the sandbox forbids event taps that swallow keys and the private APIs.

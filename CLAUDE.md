# Lineup – notes for Claude Code

macOS window switcher like Alt+Tab on Windows (Swift 6, SwiftUI + AppKit, Swift Package Manager, macOS 15+).
Agent app (`LSUIElement`, menu bar icon only). **Read [PLAN.md](PLAN.md) first** – milestones, technical
notes and risks; update it when a milestone is done or the plan changes.

- `Sources/LineupCore` – pure logic, no AppKit: window list building (`WindowListBuilder`), MRU order
  (`RecentWindows`), tile grid and thumbnail sizes (`GridLayout`, `aspectFit`), selection (`Selection`), hotkey state machine + shortcut setting (`HotkeyStateMachine`,
  `ShortcutChoice`). Tested in `Tests/LineupCoreTests`.
- `Sources/CPrivate` – private macOS APIs: declarations of `_AXUIElementGetWindow` and the CGS symbolic hot
  keys, plus `WT*` C wrappers that look SkyLight/HIServices symbols up with `dlsym` (Spaces, window lists,
  `WTFocusWindow`, remote-token elements, `WTCopyWindowImage`). Keep every private API here, prefer `dlsym`
  for new ones (a missing symbol must not stop the app from launching) and always have a public fallback.
- `Sources/Lineup` – the app: `KeyboardTap` (CGEventTap), `FocusTracker` (AXObserver + NSWorkspace → MRU),
  `SystemAppSwitcher` (turning the system ⌘Tab off/on, signal handlers, `--watchdog` process),
  `WindowSource` (AX + CGWindowList, switching), `OtherSpaces` (`Spaces`, `RemoteWindowSearch` – windows on
  other Spaces), `DebugSpaces` (`LINEUP_SPACES=1`), `ThumbnailStore` + `ScreenRecordingPermission`
  (ScreenCaptureKit previews), `SwitcherController`, `SwitcherPanel` (non-activating
  NSPanel + SwiftUI), `Permissions`, `main.swift` (menu bar, state polling, debug commands).

**Formerly WinTab** (renamed in 0.2.0 because of the Wacom "Wintab" API; bundle ID was
`io.github.furcenzo.wintab`). `AppSettings.migrateLegacyDefaults()` copies the old defaults once and
`SystemAppSwitcher.quitLegacyApp()` quits a still running WinTab; the tap's `cask_renames.json` maps
`wintab` to `lineup` (users still run `brew install --cask furcenzo/tap/lineup` once: Homebrew's per-cask
trust doesn't follow renames, so `brew upgrade` skips it). Keep these until nobody runs WinTab any more.

**Never leave the system ⌘Tab turned off.** Its state is global and outlives Lineup. Any code path that
stops Lineup's keyboard tap must let `CommandTabGuard` turn it back on. If it ever stays off during
development, start and quit Lineup (or log out).

App icon: `Assets/AppIcon.icns` + `AppIcon.png`, drawn by `scripts/icon/AppIcon.swift` (Core Graphics);
regenerate both with `./scripts/make-icon.sh` and commit them. `scripts/build-app.sh` copies the .icns into the bundle.

Build: `swift build`, tests: `swift test`, app bundle: `./scripts/build-app.sh` → `build/Lineup Dev.app`,
build + restart: `./scripts/run.sh [sk|en]`.

## Shared scripts (mac-app-kit)

`scripts/` (except `scripts/icon/` and `scripts/release-notes.md`), `.githooks/` and `.claude/settings.json`
are copies from mac-app-kit (`../mac-app-kit`, shared with Brew GUI and the author's other Mac apps). Don't edit
them here: change them in the kit and run its `./sync.sh` (`./sync.sh --check` lists differences). Lineup's
settings for them (name, bundle ID, repository, cask, dev.furian.sk slug, menu bar app…) are in `app.conf`.

**Development builds are "Lineup Dev"** (bundle ID `io.github.furcenzo.lineup.dev`, `CHANNEL=dev`, the default
of `build-app.sh`); only `release.sh` and `install-local.sh` build the real `io.github.furcenzo.lineup`
(`CHANNEL=release`) and they delete their staging copies afterwards. Reason: the login item, Spotlight and
LaunchServices pick an app by bundle ID – a second copy with the real ID once made
the login item start the dev build, and a dev build named `build/Lineup.app` was opened by Spotlight. "Lineup Dev" needs its own Accessibility / Screen Recording permissions
(granted once); debug commands can also run against `/Applications/Lineup.app` (they never touch ⌘Tab).

**The author's own installation:** `/Applications/Lineup.app` is managed by Homebrew (cask
`furcenzo/tap/lineup`, adopted with `brew install --cask --adopt`) but contains a build signed with
"Lineup Local Dev", so the permissions stay. `./scripts/run.sh` quits it while testing a dev build ("Lineup Dev") – start it
again with `open /Applications/Lineup.app`. After a release: `brew upgrade --cask lineup`, then
`./scripts/install-local.sh` (puts a dev-signed build of the latest tag back; Homebrew only checks the version).

## Code signing and permissions

Lineup needs the Accessibility permission and, for previews, Screen Recording. macOS ties it to the code signature,
so development builds are signed with the local self-signed certificate **"Lineup Local Dev"**
(`scripts/build-app.sh` uses it automatically when it exists, otherwise signs ad-hoc with a warning).
The certificate is created once by the user with `./scripts/setup-dev-signing.sh` – it needs the login
password, so never run it for the user without asking; give them the command instead.
After a signing identity change, the user has to remove Lineup from System Settings → Privacy & Security →
Accessibility and add it again.

Testing without a keyboard (results on stdout; `open --stdout <file> --env …` works too):
`"build/Lineup Dev.app/Contents/MacOS/Lineup"` with `LINEUP_LIST=1` (print the window list),
`LINEUP_SNAPSHOT=/x.png` (render the overlay to PNG, no screen recording needed), `LINEUP_CYCLE=<n>`
(open/close smoke test), `LINEUP_SPACES=1` (private Space APIs report), `LINEUP_VIEW=settings|permissions`
with `LINEUP_SNAPSHOT` (image of those windows), `LINEUP_ONLY_APPS=<bundle IDs>` (list only those apps) or
`LINEUP_SWITCH=<n>`
(switch to the n-th window and print the frontmost app/window). Run the binary inside the signed bundle –
the permission belongs to the bundle. Debug runs never touch the system ⌘Tab. The running app logs focus
changes: `log stream --level debug --predicate 'subsystem == "io.github.furcenzo.lineup"'`.

**Screenshots** (`Assets/screenshots/`, used by the README) must never show the user's real windows – they
contain chats, phone numbers and the user's name (even window titles, e.g. Chess shows the account name, the
Clock shows the city). Open neutral demo apps that are not running yet (Safari on the Lineup GitHub page,
Preview with the icon, Calculator, Font Book), check their titles with `LINEUP_LIST=1` first, snapshot with
`LINEUP_ONLY_APPS`, then quit only those demo apps. Ask the user before opening apps on their Mac.

## Localization – the app is bilingual (English + Slovak)

Every change that adds or changes a user-facing text must keep **both languages** complete.

- **Code contains English only.** The English text is the localization key. Never write Slovak
  (or any other language) into string literals in `Sources/` – the check fails on Slovak diacritics.
- **Slovak goes to** `Sources/Lineup/Resources/sk.lproj/Localizable.strings` (key = the English text,
  exactly as in code, including punctuation and `…`). Keep the file sorted alphabetically (case-insensitive).
  `en.lproj` stays empty on purpose.
- Interpolated values become format specifiers in the key: `Text("Switch to \(name)?")` →
  `"Switch to %@?"`; `Int` → `%lld`, `Int32` → `%d`, `String` → `%@`. The translation must use the same
  specifiers (use `%1$@`, `%2$@` if the order has to change).
- **Which APIs translate automatically:** SwiftUI initializers that take a *string literal*
  (`Text("…")`, `Button("…")`, `Label`, `Toggle`, `Section`, `.help("…")`…) use `LocalizedStringKey`.
  A `String` **variable** passed to them is shown verbatim (not translated).
  - For texts built in code (menus, `NSAlert`, window titles) use `String(localized: "…")`.
  - Text that must not be translated (window titles, app names): pass a `String` variable or use
    `Text(verbatim:)`.
- Avoid grammar that depends on the number (Slovak has 3 plural forms): prefer `"Windows: %lld"`.
- Names of macOS settings in Slovak follow the Slovak macOS UI (Systémové nastavenia, Súkromie a bezpečnosť,
  Prístupnosť, Nahrávanie obrazovky).
- **Always run** `./scripts/check-localization.sh` after changing texts. It lists every localizable string
  via the compiler and fails on missing translations, mismatched format specifiers, or Slovak in code;
  it warns about unused translations (delete them).
- Enforced by hooks: the Claude Code `Stop` hook (`.claude/settings.json` →
  `scripts/hooks/claude-stop-l10n.sh`) and the git pre-commit hook (`.githooks/pre-commit`,
  enable with `git config core.hooksPath .githooks`).
- To check the UI in a given language: `./scripts/run.sh sk` (or `en`).

## Releases

`./scripts/release.sh <version>` builds a universal (Apple silicon + Intel), ad-hoc signed app into
`build/release/` (never over the dev-signed `build/Lineup Dev.app`) and zips it into `build/`. `./scripts/release.sh <version> --publish` also tags `v<version>`, pushes the tag and creates
a GitHub Release with the zip; its "What's new" is the `## <version>` section of `CHANGELOG.md`
(the script refuses to publish without it), the download instructions come from `scripts/release-notes.md`, and it bumps `version`/`sha256` of `Casks/lineup.rb` in the
`Furcenzo/homebrew-tap` repository (shared with Brew GUI; users install with
`brew install --cask furcenzo/tap/lineup`). When you make a user-facing change, add a line under
`## Unreleased` in `CHANGELOG.md`; at release time rename that heading to the version. Publishing is public
and irreversible – only run `--publish` when the user explicitly asked for it. The repository is public at
github.com/Furcenzo/lineup (pushed over HTTPS).
At the end, `--publish` also runs `~/Projects/Private/dev.furian.sk/scripts/update-site.sh lineup` (if that
repository is on this Mac): it copies a changed icon or screenshots to the showroom site https://dev.furian.sk and
deploys it. Version and download link there follow the latest GitHub Release by themselves. New or renamed
screenshots and changed feature texts have to be edited in that site's `public/index.html` by hand.

## Conventions

- Every source file starts with `// SPDX-License-Identifier: GPL-3.0-or-later` and
  `// Copyright (C) 2026 Furcenzo` (in `Package.swift` after the `swift-tools-version` line; `#` comments
  in shell scripts). Code taken over from AltTab keeps its original copyright line too.
- README, CLAUDE.md, PLAN.md, commit messages and code comments are in English.
- Bundle ID is `io.github.furcenzo.lineup`.
- Sister project with the same conventions: `../Brew GUI` (github.com/Furcenzo/brew-gui).

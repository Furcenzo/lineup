# WinTab – notes for Claude Code

macOS window switcher like Alt+Tab on Windows (Swift 6, SwiftUI + AppKit, Swift Package Manager, macOS 15+).
Agent app (`LSUIElement`, menu bar icon only). **Read [PLAN.md](PLAN.md) first** – milestones, technical
notes and risks; update it when a milestone is done or the plan changes.

- `Sources/WinTabCore` – pure logic, no AppKit: window list building (`WindowListBuilder`), MRU order
  (`RecentWindows`), tile grid and thumbnail sizes (`GridLayout`, `aspectFit`), selection (`Selection`), hotkey state machine + shortcut setting (`HotkeyStateMachine`,
  `ShortcutChoice`). Tested in `Tests/WinTabCoreTests`.
- `Sources/CPrivate` – private macOS APIs: declarations of `_AXUIElementGetWindow` and the CGS symbolic hot
  keys, plus `WT*` C wrappers that look SkyLight/HIServices symbols up with `dlsym` (Spaces, window lists,
  `WTFocusWindow`, remote-token elements, `WTCopyWindowImage`). Keep every private API here, prefer `dlsym`
  for new ones (a missing symbol must not stop the app from launching) and always have a public fallback.
- `Sources/WinTab` – the app: `KeyboardTap` (CGEventTap), `FocusTracker` (AXObserver + NSWorkspace → MRU),
  `SystemAppSwitcher` (turning the system ⌘Tab off/on, signal handlers, `--watchdog` process),
  `WindowSource` (AX + CGWindowList, switching), `OtherSpaces` (`Spaces`, `RemoteWindowSearch` – windows on
  other Spaces), `DebugSpaces` (`WINTAB_SPACES=1`), `ThumbnailStore` + `ScreenRecordingPermission`
  (ScreenCaptureKit previews), `SwitcherController`, `SwitcherPanel` (non-activating
  NSPanel + SwiftUI), `Permissions`, `main.swift` (menu bar, state polling, debug commands).

**Never leave the system ⌘Tab turned off.** Its state is global and outlives WinTab. Any code path that
stops WinTab's keyboard tap must let `CommandTabGuard` turn it back on. If it ever stays off during
development, start and quit WinTab (or log out).

Build: `swift build`, tests: `swift test`, app bundle: `./scripts/build-app.sh` → `build/WinTab.app`,
build + restart: `./scripts/run.sh [sk|en]`.

## Code signing and permissions

WinTab needs the Accessibility permission and, for previews, Screen Recording. macOS ties it to the code signature,
so development builds are signed with the local self-signed certificate **"WinTab Local Dev"**
(`scripts/build-app.sh` uses it automatically when it exists, otherwise signs ad-hoc with a warning).
The certificate is created once by the user with `./scripts/setup-dev-signing.sh` – it needs the login
password, so never run it for the user without asking; give them the command instead.
After a signing identity change, the user has to remove WinTab from System Settings → Privacy & Security →
Accessibility and add it again.

Testing without a keyboard (results on stdout; `open --stdout <file> --env …` works too):
`build/WinTab.app/Contents/MacOS/WinTab` with `WINTAB_LIST=1` (print the window list),
`WINTAB_SNAPSHOT=/x.png` (render the overlay to PNG, no screen recording needed), `WINTAB_CYCLE=<n>`
(open/close smoke test), `WINTAB_SPACES=1` (private Space APIs report) or `WINTAB_SWITCH=<n>`
(switch to the n-th window and print the frontmost app/window). Run the binary inside the signed bundle –
the permission belongs to the bundle. Debug runs never touch the system ⌘Tab. The running app logs focus
changes: `log stream --level debug --predicate 'subsystem == "io.github.furcenzo.wintab"'`.

## Localization – the app is bilingual (English + Slovak)

Every change that adds or changes a user-facing text must keep **both languages** complete.

- **Code contains English only.** The English text is the localization key. Never write Slovak
  (or any other language) into string literals in `Sources/` – the check fails on Slovak diacritics.
- **Slovak goes to** `Sources/WinTab/Resources/sk.lproj/Localizable.strings` (key = the English text,
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

`./scripts/release.sh <version>` builds a universal (Apple silicon + Intel), ad-hoc signed app and zips it
into `build/`. `./scripts/release.sh <version> --publish` also tags `v<version>`, pushes the tag and creates
a GitHub Release with the zip; its "What's new" is the `## <version>` section of `CHANGELOG.md`
(the script refuses to publish without it). When you make a user-facing change, add a line under
`## Unreleased` in `CHANGELOG.md`; at release time rename that heading to the version. Publishing is public
and irreversible – only run `--publish` when the user explicitly asked for it. The repository is not on
GitHub yet; the user publishes it themselves.

## Conventions

- Every source file starts with `// SPDX-License-Identifier: GPL-3.0-or-later` and
  `// Copyright (C) 2026 Furcenzo` (in `Package.swift` after the `swift-tools-version` line; `#` comments
  in shell scripts). Code taken over from AltTab keeps its original copyright line too.
- README, CLAUDE.md, PLAN.md, commit messages and code comments are in English.
- Bundle ID is `io.github.furcenzo.wintab`.
- Sister project with the same conventions: `../Brew GUI` (github.com/Furcenzo/brew-gui).

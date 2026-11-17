# WinTab

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

A window switcher for macOS that works like **Alt+Tab on Windows**: it switches between *windows*, not apps.
Free, minimal, no upsells. Available in English and Slovak (follows the macOS language setting).

> **Status:** early development (milestone 2 of 5, see [PLAN.md](PLAN.md)). Only windows of the current
> desktop (Space) are listed; window previews and all Spaces come next.

## Usage

- Hold **⌘ Command** and press **Tab** – the switcher shows the windows of the current desktop, most recently
  used first.
- **Tab** / **→** / **↓** – next window, **⇧ Tab** / **←** / **↑** – previous window.
- Release **⌘** (or press **Return**) – switch to the selected window. A quick ⌘Tab flips to the previous window.
- **Esc** – close without switching. A mouse click on a window switches to it.
- Minimized windows are listed at the end and are restored when chosen; windows of hidden apps are shown too.

WinTab lives in the menu bar (no Dock icon). Its menu has **Shortcut**: ⌘Tab (replaces the system app
switcher, the default) or ⌥Tab (keeps the system ⌘Tab). Quit WinTab from the same menu – the system ⌘Tab
comes back as soon as WinTab quits, crashes or is force-quit (a small watchdog process, also called WinTab,
takes care of that). In password fields and with Terminal's Secure Keyboard Entry macOS hides key presses
from all apps, so ⌘Tab shows the system app switcher there.

## Permissions

WinTab needs the **Accessibility** permission to notice the shortcut, read the list of windows and bring
the chosen one to the front. On the first start it shows a window with a button to
**System Settings → Privacy & Security → Accessibility**; turn WinTab on there. WinTab does not record or
send anything.

## Requirements

- macOS 15 or later
- Swift 6 toolchain (Xcode 16 or later) to build from source

## Building

```bash
swift build
swift test
```

Build the app into `build/WinTab.app` (and restart it):

```bash
./scripts/run.sh
```

### Stable code signature for development

macOS remembers the Accessibility permission per code signature. An ad-hoc signed build gets a new
signature every time, so macOS would ask for the permission after every build. Create a local
self-signed certificate once (it asks for your login password):

```bash
./scripts/setup-dev-signing.sh
```

From then on `scripts/build-app.sh` signs every build with **"WinTab Local Dev"** and the permission
survives rebuilds. The certificate only works on your Mac; remove it any time in Keychain Access.

## Debugging

The binary inside the bundle accepts environment variables (output on stdout):

- `WINTAB_LIST=1` – print the windows the switcher would offer and quit,
- `WINTAB_SNAPSHOT=/path.png` – save an image of the switcher overlay and quit (no screen recording needed),
- `WINTAB_SWITCH=<n>` – switch to the n-th window of the list and print which window is in front afterwards,
- `WINTAB_CYCLE=<n>` – open, move and close the switcher overlay n times (smoke test) and quit.

The running app logs focus changes and window lists:

```bash
log stream --level debug --predicate 'subsystem == "io.github.furcenzo.wintab"'
```

```bash
WINTAB_LIST=1 build/WinTab.app/Contents/MacOS/WinTab
```

## Translations

Texts in the code are English; translations live in `Sources/WinTab/Resources/<language>.lproj/Localizable.strings`
(the key is the English text). After changing any user-facing text, run:

```bash
./scripts/check-localization.sh
```

To run it automatically before every commit, enable the bundled git hook once per clone:

```bash
git config core.hooksPath .githooks
```

See [CLAUDE.md](CLAUDE.md) for the detailed rules.

## Project structure

- `Sources/WinTabCore` – window list ordering, selection and hotkey logic (no UI, tested).
- `Sources/CPrivate` – declarations of private macOS APIs.
- `Sources/WinTab` – the app: keyboard event tap, ⌘Tab takeover, focus tracking, window list via
  Accessibility, overlay panel, menu bar.
- `Tests/WinTabCoreTests` – tests for the core logic.
- `scripts/` – app bundle build, dev signing setup, release, translation check and the Claude Code hook.

## Acknowledgments

[AltTab](https://github.com/lwouis/alt-tab-macos) by Louis Pontoise and contributors (GPL-3.0) – the local
code signing setup is based on its `scripts/codesign`, turning off the system ⌘Tab follows its use of
`CGSSetSymbolicHotKeyEnabled`, and later milestones (all Spaces, precise window focus) will build on its
research into private macOS APIs.

## License

Copyright (C) 2026 Furcenzo

This program is free software: you can redistribute it and/or modify it under the terms of the
[GNU General Public License](LICENSE) as published by the Free Software Foundation, either version 3
of the License, or (at your option) any later version (`GPL-3.0-or-later`).
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY.
See the [LICENSE](LICENSE) file for the full text.

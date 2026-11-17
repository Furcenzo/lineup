# Changelog

User-facing changes in each release. `scripts/release.sh <version> --publish` copies the section of that
version into the GitHub Release notes, so add a section before publishing.

## Unreleased

- Window switcher on `⌘ Tab` (replaces the system app switcher) for the windows of the current desktop:
  app icon and window title, Tab / arrows / ⇧Tab to move, release ⌘ to switch, Esc to cancel, mouse click to
  switch. Minimized windows and hidden apps are restored when chosen.
- Windows are ordered by when you last used them; minimized windows come last.
- Menu bar → Shortcut: switch to `⌥ Tab` to keep the system ⌘Tab. The system ⌘Tab always comes back when
  WinTab quits, and works in password fields.
- Menu bar icon (no Dock icon) and a guide for the Accessibility permission.
- English and Slovak user interface.

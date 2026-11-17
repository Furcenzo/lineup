# Changelog

User-facing changes in each release. `scripts/release.sh <version> --publish` copies the section of that
version into the GitHub Release notes, so add a section before publishing.

## Unreleased

## 0.2.0

- **WinTab is now Lineup.** The old name clashed with the Wintab tablet API. Homebrew users get Lineup with
  `brew upgrade` (the `wintab` cask moves to `lineup`). Your settings come along, but macOS sees a new app:
  allow Accessibility (and Screen Recording for previews) again, turn on Open at Login in Settings again if
  you used it, and remove WinTab from those lists in System Settings. A WinTab that still runs is quit.

## 0.1.2

- Opening WinTab again (Finder, Spotlight) while it runs shows its Settings – handy when the menu bar icon
  is hidden.

## 0.1.1

- A click outside the switcher closes it without switching, like Esc ([#1](https://github.com/Furcenzo/lineup/issues/1)).
- The selected window tile has a × button that closes the window; with ⇧ held it turns red and force quits the
  app ([#2](https://github.com/Furcenzo/lineup/issues/2)).

## 0.1.0

- Window switcher on `⌘ Tab` (replaces the system app switcher) – like Alt+Tab on Windows it switches
  windows, not apps: window previews with the app icon, Tab / arrows / ⇧Tab to move, release ⌘ to switch,
  Esc to cancel, mouse click to switch. A quick ⌘Tab flips to the previous window.
- Windows from all desktops (Spaces) and fullscreen apps; choosing one switches to its desktop and to exactly
  that window, also between several windows of one app. Minimized windows and hidden apps are restored.
- Windows are ordered by when you last used them; minimized windows come last.
- `⌥ Tab` instead, if you want to keep the system ⌘Tab. The system ⌘Tab always comes back when WinTab quits,
  and works in password fields.
- Settings (menu bar → Settings…, ⌘,): shortcut, previews, all desktops, minimized windows, windows of hidden
  apps, excluded apps, which screen shows the switcher, open at login.
- A welcome window guides you through the Accessibility and Screen Recording permissions and shows their state.
- Menu bar icon only, no Dock icon; an app icon for Finder, the About window and the welcome window.
- English and Slovak user interface.

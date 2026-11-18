## What's new

@CHANGES@

## Download

**[@ZIP@](@ZIP_URL@)** – universal app (Apple silicon + Intel), macOS 15 or later, English and Slovak.

1. Unzip it and move **Lineup.app** to /Applications.
2. The app is not notarized by Apple, so the first launch is blocked by Gatekeeper. Open
   **System Settings → Privacy & Security** and click **Open Anyway** next to “Lineup”, or run:
   `xattr -dr com.apple.quarantine "/Applications/Lineup.app"`

3. Start Lineup – its window guides you through the permissions: **Accessibility** (required) and
   **Screen & System Audio Recording** (optional, for window previews).

Or install it with Homebrew: `brew install --cask furcenzo/tap/lineup`

Lineup replaces ⌘Tab with a window switcher (Settings can switch it to ⌥Tab). After updating Lineup, macOS
may ask for the permissions again: remove Lineup from both lists in System Settings and allow it anew.

SHA-256: `@SHA@`

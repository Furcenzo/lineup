#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Furcenzo
#
# Builds a downloadable release of WinTab.
#   ./scripts/release.sh 0.2.0            build + zip into build/ (nothing is published)
#   ./scripts/release.sh 0.2.0 --publish  also tag v0.2.0, push the tag and create a GitHub Release
#                                         (its "What's new" comes from the "## 0.2.0" section of CHANGELOG.md)
#                                         and update the cask in the Furcenzo/homebrew-tap repository
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
PUBLISH="${2:-}"
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "usage: $0 <major.minor.patch> [--publish]" >&2
    exit 1
fi
TAG="v$VERSION"
ZIP="build/WinTab-$VERSION.zip"

if [[ "$PUBLISH" == "--publish" ]]; then
    [[ -z "$(git status --porcelain)" ]] || { echo "The working tree has uncommitted changes." >&2; exit 1; }
    [[ "$(git branch --show-current)" == "main" ]] || { echo "Releases are made from main." >&2; exit 1; }
    git fetch --quiet origin main --tags
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "main is not in sync with origin/main – push or pull first." >&2; exit 1; }
    ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "Tag $TAG already exists." >&2; exit 1; }
    # The "## <version>" section of CHANGELOG.md, without its heading.
    CHANGES="$(awk -v v="## $VERSION" '$0 == v { found = 1; next } found && /^## / { exit } found' CHANGELOG.md \
        | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"
    [[ -n "$CHANGES" ]] || { echo "CHANGELOG.md has no \"## $VERSION\" section with the changes – add it first." >&2; exit 1; }
fi

swift test
./scripts/check-localization.sh
# Public builds are ad-hoc signed: the local "WinTab Local Dev" certificate is only for this Mac.
VERSION="$VERSION" UNIVERSAL=1 CHANNEL=release SIGN_IDENTITY=- OUTPUT_DIR=build/release ./scripts/build-app.sh

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "build/release/WinTab.app" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
# Only the zip is needed. A second WinTab.app with the real bundle ID left on disk could stand in for the
# installed one (login item, Spotlight).
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u build/release/WinTab.app 2>/dev/null || true
rm -rf build/release
echo "Release archive: $PWD/$ZIP"
echo "SHA-256: $SHA"

[[ "$PUBLISH" == "--publish" ]] || exit 0

NOTES="$(mktemp)"
TAP_DIR="$(mktemp -d)"
trap 'rm -rf "$NOTES" "$TAP_DIR"' EXIT
cat > "$NOTES" <<EOF
## What's new

$CHANGES

## Download

**[WinTab-$VERSION.zip](https://github.com/Furcenzo/wintab/releases/download/$TAG/WinTab-$VERSION.zip)** – universal app (Apple silicon + Intel), macOS 15 or later, English and Slovak.

1. Unzip it and move **WinTab.app** to /Applications.
2. The app is not notarized by Apple, so the first launch is blocked by Gatekeeper. Open
   **System Settings → Privacy & Security** and click **Open Anyway** next to “WinTab”, or run:
   \`xattr -dr com.apple.quarantine "/Applications/WinTab.app"\`

3. Start WinTab – its window guides you through the permissions: **Accessibility** (required) and
   **Screen & System Audio Recording** (optional, for window previews).

Or install it with Homebrew: \`brew install --cask furcenzo/tap/wintab\`

WinTab replaces ⌘Tab with a window switcher (Settings can switch it to ⌥Tab). After updating WinTab, macOS
may ask for the permissions again: remove WinTab from both lists in System Settings and allow it anew.

SHA-256: \`$SHA\`
EOF

git tag -a "$TAG" -m "WinTab $VERSION"
git push origin "$TAG"
gh release create "$TAG" "$ZIP" --title "WinTab $VERSION" --notes-file "$NOTES" --generate-notes

# Point the Homebrew cask (brew install --cask furcenzo/tap/wintab) at the new release.
git clone --quiet https://github.com/Furcenzo/homebrew-tap.git "$TAP_DIR"
CASK="$TAP_DIR/Casks/wintab.rb"
perl -pi -e "s/^  version \".*\"/  version \"$VERSION\"/; s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
grep -q "version \"$VERSION\"" "$CASK" && grep -q "sha256 \"$SHA\"" "$CASK" || { echo "Updating $CASK failed." >&2; exit 1; }
git -C "$TAP_DIR" commit --quiet --all --message "wintab $VERSION"
git -C "$TAP_DIR" push --quiet origin HEAD
echo "Updated furcenzo/tap: wintab $VERSION"

# Refresh the showroom website https://dev.furian.sk (app icon and screenshots; its version numbers and download
# links follow the latest release by themselves). Runs only where that site's repository is checked out (the
# author's Mac; SHOWROOM_SITE_DIR overrides the path). A failure here does not undo the release.
SITE_UPDATE="${SHOWROOM_SITE_DIR:-$HOME/Projects/Private/dev.furian.sk}/scripts/update-site.sh"
if [[ -x "$SITE_UPDATE" ]]; then
    "$SITE_UPDATE" wintab || echo "Updating dev.furian.sk failed – run $SITE_UPDATE wintab later." >&2
fi

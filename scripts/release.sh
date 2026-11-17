#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Furcenzo
#
# Builds a downloadable release of WinTab.
#   ./scripts/release.sh 0.2.0            build + zip into build/ (nothing is published)
#   ./scripts/release.sh 0.2.0 --publish  also tag v0.2.0, push the tag and create a GitHub Release
#                                         (its "What's new" comes from the "## 0.2.0" section of CHANGELOG.md)
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
VERSION="$VERSION" UNIVERSAL=1 SIGN_IDENTITY=- OUTPUT_DIR=build/release ./scripts/build-app.sh

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "build/release/WinTab.app" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
echo "Release archive: $PWD/$ZIP"
echo "SHA-256: $SHA"

[[ "$PUBLISH" == "--publish" ]] || exit 0

NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
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

WinTab replaces ⌘Tab with a window switcher (Settings can switch it to ⌥Tab). After updating WinTab, macOS
may ask for the permissions again: remove WinTab from both lists in System Settings and allow it anew.

SHA-256: \`$SHA\`
EOF

git tag -a "$TAG" -m "WinTab $VERSION"
git push origin "$TAG"
gh release create "$TAG" "$ZIP" --title "WinTab $VERSION" --notes-file "$NOTES" --generate-notes

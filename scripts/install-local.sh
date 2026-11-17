#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Furcenzo
#
# For the author's own Mac: installs a build signed with "Lineup Local Dev" as /Applications/Lineup.app,
# so the permissions survive updates (the public releases are ad-hoc signed and would lose them).
#   ./scripts/install-local.sh          version = the latest git tag (e.g. v0.1.1 → 0.1.1)
#   ./scripts/install-local.sh 0.2.0
#
# Homebrew manages /Applications/Lineup.app (cask furcenzo/tap/lineup, adopted with
# `brew install --cask --adopt`). After a release: `brew upgrade --cask lineup`, then run this script –
# Homebrew only checks the version number, so it keeps treating the replaced app as its own.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(git describe --tags --abbrev=0 | sed 's/^v//')}"
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "usage: $0 [major.minor.patch]" >&2
    exit 1
fi
security find-identity -v -p codesigning | grep -q '"Lineup Local Dev"' \
    || { echo "The \"Lineup Local Dev\" certificate is missing – run scripts/setup-dev-signing.sh first." >&2; exit 1; }

VERSION="$VERSION" CHANNEL=release OUTPUT_DIR=build/install SIGN_IDENTITY="Lineup Local Dev" ./scripts/build-app.sh
# Quitting Lineup (SIGTERM) turns the system ⌘Tab back on; the new one takes it over again.
pkill -x Lineup 2>/dev/null && sleep 1 || true
rm -rf /Applications/Lineup.app
ditto build/install/Lineup.app /Applications/Lineup.app
# Keep /Applications the only app with the real bundle ID (the login item follows the bundle ID).
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u build/install/Lineup.app 2>/dev/null || true
rm -rf build/install
open /Applications/Lineup.app
echo "Installed Lineup $VERSION (signed with Lineup Local Dev) into /Applications and started it."

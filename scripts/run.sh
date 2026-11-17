#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Furcenzo
#
# Development loop: build build/WinTab.app, quit the running WinTab and start the new build.
#   ./scripts/run.sh          English UI (or the macOS language)
#   ./scripts/run.sh sk       force a language
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh
pkill -x WinTab 2>/dev/null && sleep 0.5 || true
if [[ -n "${1:-}" ]]; then
    open -n build/WinTab.app --args -AppleLanguages "($1)"
else
    open -n build/WinTab.app
fi
echo "WinTab Dev is running – look for its icon in the menu bar."
if [[ -d /Applications/WinTab.app ]]; then
    echo "(The installed WinTab was quit. Back to it: open /Applications/WinTab.app)"
fi

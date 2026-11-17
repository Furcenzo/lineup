#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Furcenzo
#
# Builds the release version and packages it as build/Lineup.app.
#   VERSION=1.2.3      version written to Info.plist (default 0.1.0)
#   UNIVERSAL=1        build for both Apple silicon and Intel (used for public releases)
#   SIGN_IDENTITY=…    code signing identity; default: "Lineup Local Dev" when it exists in the keychain
#                      (see scripts/setup-dev-signing.sh), otherwise ad-hoc ("-")
#   CHANNEL=release    the real app (bundle ID io.github.furcenzo.lineup, name Lineup) – used by release.sh
#                      and install-local.sh. Default "dev": bundle ID io.github.furcenzo.lineup.dev, name
#                      "Lineup Dev", so development builds never stand in for the installed app (login item,
#                      Spotlight, LaunchServices pick an app by its bundle ID) and keep their own permissions.
#   OUTPUT_DIR=…       where Lineup.app goes (default build; releases use build/release so they don't
#                      replace the development app the permissions belong to)
#
# Why the signature matters: macOS remembers the Accessibility permission per code signature. With an
# ad-hoc signature every build looks like a new app and the permission has to be granted again.
set -euo pipefail
cd "$(dirname "$0")/.."

DEV_IDENTITY="Lineup Local Dev"
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    if security find-identity -p codesigning | grep -q "\"$DEV_IDENTITY\""; then
        SIGN_IDENTITY="$DEV_IDENTITY"
    else
        SIGN_IDENTITY="-"
        echo "warning: no \"$DEV_IDENTITY\" certificate – signing ad-hoc, so macOS will ask for the" >&2
        echo "         Accessibility permission again after every build. Run scripts/setup-dev-signing.sh once." >&2
    fi
fi

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release "${ARCH_FLAGS[@]}"
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)/Lineup"

APP="${OUTPUT_DIR:-build}/Lineup.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -f "$BIN" "$APP/Contents/MacOS/Lineup"

# App icon (drawn by scripts/make-icon.swift)
cp -f Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Translations (English is the development language, see CLAUDE.md)
LOCALIZATIONS=()
for lproj in Sources/Lineup/Resources/*.lproj; do
    cp -R "$lproj" "$APP/Contents/Resources/"
    LOCALIZATIONS+=("<string>$(basename "$lproj" .lproj)</string>")
done

VERSION="${VERSION:-0.1.0}"
if [[ "${CHANNEL:-dev}" == "release" ]]; then
    BUNDLE_ID="io.github.furcenzo.lineup"
    DISPLAY_NAME="Lineup"
else
    BUNDLE_ID="io.github.furcenzo.lineup.dev"
    DISPLAY_NAME="Lineup Dev"
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key><string>${DISPLAY_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>Lineup</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array>${(j::)LOCALIZATIONS}</array>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Copyright (C) 2026 Furcenzo. GPL-3.0-or-later.</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint -s "$APP/Contents/Info.plist"
codesign --force --sign "$SIGN_IDENTITY" "$APP" >/dev/null
echo "Done: $PWD/$APP ($BUNDLE_ID, signed: $SIGN_IDENTITY)"

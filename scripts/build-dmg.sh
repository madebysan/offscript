#!/bin/bash
# Builds Offscript as a universal app, re-signs Sparkle's nested code with the
# Developer ID (a plain xcodebuild leaves it ad-hoc signed, which notarization
# rejects), notarizes and staples the app, and packages dist/Offscript-<version>.dmg,
# also notarized and stapled. Write the update feed afterwards with the
# ship-macos make-appcast.sh script.
#
# Prerequisites: XcodeGen, the Developer ID Application certificate, and
# notarytool credentials stored as the keychain profile "notarytool"
# (override with NOTARY_PROFILE).
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Offscript"
SCHEME="Cue"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Santiago Alonso Alexandre (QAMM2A6WRQ)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/cue-release.XXXXXX")"

xcodegen generate
xcodebuild -project "Cue.xcodeproj" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$WORK/dd" -destination 'generic/platform=macOS' clean build \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=QAMM2A6WRQ CODE_SIGN_IDENTITY="Developer ID Application" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO

APP="$WORK/dd/Build/Products/Release/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

# Keep the app's processed entitlements, then sign Sparkle inside-out and the app last.
codesign -d --entitlements - --xml "$APP" > "$WORK/entitlements.plist"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
FW="$APP/Contents/Frameworks/Sparkle.framework"
codesign -f -o runtime --timestamp -s "$SIGN_IDENTITY" "$FW/Versions/B/XPCServices/Installer.xpc"
codesign -f -o runtime --timestamp --preserve-metadata=entitlements -s "$SIGN_IDENTITY" "$FW/Versions/B/XPCServices/Downloader.xpc"
codesign -f -o runtime --timestamp -s "$SIGN_IDENTITY" "$FW/Versions/B/Autoupdate"
codesign -f -o runtime --timestamp -s "$SIGN_IDENTITY" "$FW/Versions/B/Updater.app"
codesign -f -o runtime --timestamp -s "$SIGN_IDENTITY" "$FW"
codesign -f -o runtime --timestamp --entitlements "$WORK/entitlements.plist" -s "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

ditto -c -k --keepParent "$APP" "$WORK/app.zip"
xcrun notarytool submit "$WORK/app.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

mkdir -p dist "$WORK/stage"
DMG="dist/$APP_NAME-$VERSION.dmg"
ditto "$APP" "$WORK/stage/$APP_NAME.app"
ln -s /Applications "$WORK/stage/Applications"
cp README.md LICENSE THIRD_PARTY_NOTICES.md "$WORK/stage/"
hdiutil create -volname "$APP_NAME" -srcfolder "$WORK/stage" -ov -format UDZO "$DMG"
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"

echo "Done: $DMG"

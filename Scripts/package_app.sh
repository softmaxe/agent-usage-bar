#!/bin/bash
# Assembles AgentUsageBar.app from a release build.
#
# SwiftPM cannot emit an app bundle, so the layout is built by hand: a release binary, an
# Info.plist marking the app as an agent (no Dock icon), and an ad-hoc signature. Ad-hoc is
# enough here because the only keychain read goes through /usr/bin/security, whose access grant
# belongs to that binary rather than to this one.
set -euo pipefail

APP_NAME="AgentUsageBar"
BUNDLE_ID="com.agentusagebar.app"
VERSION="${VERSION:-0.1.0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

cd "$ROOT"

echo "==> Building release binary"
swift build -c release --product "$APP_NAME"
BINARY="$(swift build -c release --product "$APP_NAME" --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- Menu bar only: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Built $APP"
du -sh "$APP" | awk '{print "    size: " $1}'
echo "    Run it with: open \"$APP\""
echo "    Install it with: cp -R \"$APP\" /Applications/"

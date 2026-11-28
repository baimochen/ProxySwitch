#!/bin/bash
# 编译 Universal Binary（arm64 + x86_64）并打包成菜单栏应用及 dist zip 产物
set -e
cd "$(dirname "$0")"
APP="ProxySwitch.app"
DIST_ZIP="dist/ProxySwitch-macos-universal.zip"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist

TMP_ARM64=$(mktemp)
TMP_X86_64=$(mktemp)
trap 'rm -f "$TMP_ARM64" "$TMP_X86_64"' EXIT

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  -o "$TMP_ARM64" ProxySwitch.swift \
  -framework Cocoa -framework SystemConfiguration

swiftc -O -swift-version 5 -target x86_64-apple-macos13.0 \
  -o "$TMP_X86_64" ProxySwitch.swift \
  -framework Cocoa -framework SystemConfiguration

lipo -create "$TMP_ARM64" "$TMP_X86_64" -output "$APP/Contents/MacOS/ProxySwitch"
chmod +x "$APP/Contents/MacOS/ProxySwitch"

cp Info.plist "$APP/Contents/Info.plist"
cp icons/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP"

rm -f "$DIST_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DIST_ZIP"

echo "built app: $(pwd)/$APP"
echo "built zip: $(pwd)/$DIST_ZIP"

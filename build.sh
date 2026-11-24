#!/bin/bash
# 编译并打包成菜单栏应用
set -e
cd "$(dirname "$0")"
APP="ProxySwitch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 \
  -o "$APP/Contents/MacOS/ProxySwitch" ProxySwitch.swift \
  -framework Cocoa -framework SystemConfiguration
cp Info.plist "$APP/Contents/Info.plist"
cp icons/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP"
echo "built: $(pwd)/$APP"

#!/bin/zsh
# Builds build/OrangeCat.app from Sources/main.swift.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/OrangeCat.app
rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Universal binary (Apple silicon + Intel), runnable on macOS 13 and later.
for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target $arch-apple-macos13.0 -framework AppKit Sources/main.swift -o build/OrangeCat-$arch
done
lipo -create build/OrangeCat-arm64 build/OrangeCat-x86_64 -output "$APP/Contents/MacOS/OrangeCat"
rm build/OrangeCat-arm64 build/OrangeCat-x86_64

"$APP/Contents/MacOS/OrangeCat" --render-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>OrangeCat</string>
    <key>CFBundleDisplayName</key><string>橘猫</string>
    <key>CFBundleIdentifier</key><string>local.orangecat</string>
    <key>CFBundleExecutable</key><string>OrangeCat</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"

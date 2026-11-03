#!/usr/bin/env bash
set -e

echo "Building Cocoa Swift binary..."
swift build -c release

APP_NAME="Cocoa.app"
APP_DIR="./$APP_NAME"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Creating bundle structure..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

cp -R Resources/* "$RESOURCES/" 2>/dev/null || true
cp .build/release/Cocoa "$MACOS/Cocoa"
chmod +x "$MACOS/Cocoa"

cat << 'EOF' > "$CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Cocoa</string>
    <key>CFBundleIdentifier</key>
    <string>app.cocoa.focus</string>
    <key>CFBundleName</key>
    <string>Cocoa</string>
    <key>CFBundleDisplayName</key>
    <string>Cocoa</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Cocoa.app built successfully at: $(pwd)/$APP_NAME"

#!/bin/bash
set -e

# Change directory to script location
cd "$(dirname "$0")"

echo "=== Building Whisper macOS App ==="

# 1. Compile Swift package in release mode
echo "1. Compiling executable with swift build..."
swift build -c release

# 2. Re-create bundle directories
echo "2. Setting up Whisper.app bundle..."
rm -rf Whisper.app
mkdir -p Whisper.app/Contents/MacOS
mkdir -p Whisper.app/Contents/Resources

# 3. Copy binary into app bundle
echo "3. Packaging binary..."
cp .build/release/Whisper Whisper.app/Contents/MacOS/Whisper

# 4. Generate Info.plist
echo "4. Generating Info.plist..."
cat <<EOF > Whisper.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Whisper</string>
    <key>CFBundleIdentifier</key>
    <string>com.moebis.Whisper</string>
    <key>CFBundleName</key>
    <string>Whisper</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Whisper requires microphone access to record and transcribe your speech in real-time.</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
EOF

# 5. Convert source PNGs to macOS .icns files
echo "5. Creating macOS app icons using iconutil..."

create_icon() {
    local source_png="$1"
    local output_name="$2"
    local iconset="${output_name}.iconset"

    if [ ! -f "$source_png" ]; then
        echo "Missing icon source: $source_png"
        exit 1
    fi

    rm -rf "$iconset"
    mkdir -p "$iconset"

    sips -s format png -z 16 16      "$source_png" --out "$iconset/icon_16x16.png"
    sips -s format png -z 32 32      "$source_png" --out "$iconset/icon_16x16@2x.png"
    sips -s format png -z 32 32      "$source_png" --out "$iconset/icon_32x32.png"
    sips -s format png -z 64 64      "$source_png" --out "$iconset/icon_32x32@2x.png"
    sips -s format png -z 128 128    "$source_png" --out "$iconset/icon_128x128.png"
    sips -s format png -z 256 256    "$source_png" --out "$iconset/icon_128x128@2x.png"
    sips -s format png -z 256 256    "$source_png" --out "$iconset/icon_256x256.png"
    sips -s format png -z 512 512    "$source_png" --out "$iconset/icon_256x256@2x.png"
    sips -s format png -z 512 512    "$source_png" --out "$iconset/icon_512x512.png"
    sips -s format png -z 1024 1024  "$source_png" --out "$iconset/icon_512x512@2x.png"

    iconutil -c icns "$iconset"
    cp "${output_name}.icns" "Whisper.app/Contents/Resources/${output_name}.icns"
}

create_icon whisper_app_icon_dark.png AppIcon
create_icon whisper_app_icon_dark.png AppIcon-Dark
create_icon whisper_app_icon_light.png AppIcon-Light
cp whisper_app_icon_dark.png Whisper.app/Contents/Resources/whisper_app_icon_dark.png
cp whisper_app_icon_light.png Whisper.app/Contents/Resources/whisper_app_icon_light.png

# Clean up temp icon files
rm -rf AppIcon.iconset AppIcon.icns AppIcon-Dark.iconset AppIcon-Dark.icns AppIcon-Light.iconset AppIcon-Light.icns

# 6. Ad-hoc sign the bundle
echo "6. Code-signing Whisper.app..."
xattr -cr Whisper.app
codesign -s - --force --deep Whisper.app

echo "=== Build Successful! Whisper.app is ready in the workspace. ==="

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="$PWD/build/GuideCursor.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/GuideCursor "$APP/Contents/MacOS/GuideCursor"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>GuideCursor</string>
<key>CFBundleIdentifier</key><string>nl.guidecursor.prototype</string>
<key>CFBundleName</key><string>GuideCursor</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAccessibilityUsageDescription</key><string>GuideCursor reads controls in your chosen app to highlight them and provide directions. You remain in control of clicks.</string>
</dict></plist>
PLIST
# Remove Finder metadata from this generated bundle before ad-hoc signing.
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf 'Built %s\n' "$APP"

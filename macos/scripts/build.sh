#!/bin/bash
# Builds GuideCursor, then assembles, ad-hoc signs, zips and verifies the app outside the
# repository. Synced folders such as Documents can re-add Finder metadata to a bundle, which
# breaks strict signature checks ("resource fork, Finder information, or similar detritus").
# Only generated files are modified: the staging directories and $OUT/GuideCursor.app.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${GUIDECURSOR_OUT:-$HOME/Library/Caches/nl.guidecursor.prototype/build}"
case "$OUT" in
    "$HOME/Documents"*|"$HOME/Desktop"*|"$HOME/Library/Mobile Documents"*|"$HOME/Library/CloudStorage"*)
        echo "GUIDECURSOR_OUT must be outside synced folders: $OUT" >&2; exit 1 ;;
esac
# Never replace a copy that is running from the output folder.
if ps -axo comm= | grep -Fxq "$OUT/GuideCursor.app/Contents/MacOS/GuideCursor"; then
    echo "GuideCursor is running from $OUT. Quit it, then build again." >&2; exit 1
fi

swift build -c release

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/guidecursor-stage.XXXXXX")"
CHECK="$(mktemp -d "${TMPDIR:-/tmp}/guidecursor-check.XXXXXX")"
trap 'rm -rf "$STAGE" "$CHECK"' EXIT
APP="$STAGE/GuideCursor.app"
ZIP="$STAGE/GuideCursor-macOS-prototype.zip"
mkdir -p "$APP/Contents/MacOS"
ditto --norsrc --noextattr .build/release/GuideCursor "$APP/Contents/MacOS/GuideCursor"
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
xattr -cr "$APP"  # staged bundle only
codesign --force --sign - "$APP"
codesign --verify --strict --deep "$APP"

# ZIP without resource forks or extended attributes, then verify a fresh extraction.
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"
ditto -x -k "$ZIP" "$CHECK"
codesign --verify --strict --deep "$CHECK/GuideCursor.app"

mkdir -p "$OUT"
rm -rf "$OUT/GuideCursor.app"
ditto --norsrc --noextattr "$APP" "$OUT/GuideCursor.app"
ditto --norsrc --noextattr "$ZIP" "$OUT/GuideCursor-macOS-prototype.zip"
codesign --verify --strict --deep "$OUT/GuideCursor.app"
printf 'Built and verified %s\n' "$OUT/GuideCursor.app"
printf 'ZIP (extracted copy verified) %s\n' "$OUT/GuideCursor-macOS-prototype.zip"
shasum -a 256 "$OUT/GuideCursor-macOS-prototype.zip"

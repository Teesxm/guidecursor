#!/bin/bash
# Builds GuideCursor, then assembles, ad-hoc signs, zips and verifies the app outside the
# repository. Synced folders such as Documents can re-add Finder metadata to a bundle, which
# breaks strict signature checks ("resource fork, Finder information, or similar detritus").
# Only generated files are modified: the staging directories and $OUT/GuideCursor.app.
#
# Signing: ad hoc by default (also in CI). An ad hoc designated requirement is the build's cdhash, so
# macOS may treat every rebuild as a new app and require re-adding it under Accessibility.
# GUIDECURSOR_SIGN_IDENTITY="<name or SHA-1 of an existing, valid code-signing identity>" signs with
# that identity instead. The script never creates identities or changes Keychain trust.
set -euo pipefail
cd "$(dirname "$0")/.."
IDENTITY="${GUIDECURSOR_SIGN_IDENTITY:-}"
if [ -n "$IDENTITY" ]; then
    if ! security find-identity -v -p codesigning | grep -Fq -- "$IDENTITY"; then
        echo "GUIDECURSOR_SIGN_IDENTITY does not name a valid code-signing identity in your keychain: $IDENTITY" >&2
        echo "List valid identities with: security find-identity -v -p codesigning" >&2
        exit 1
    fi
    SIGN_WITH="$IDENTITY"
else
    SIGN_WITH="-"
fi
REVISION="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
if [ "$REVISION" = unknown ]; then DIRTY=unknown
elif [ -n "$(git status --porcelain -- . 2>/dev/null)" ]; then DIRTY=true
else DIRTY=false; fi
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
xml_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
SIGNING_LABEL="$( [ "$SIGN_WITH" = "-" ] && echo ad-hoc || xml_escape "$IDENTITY")"
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
cat > "$APP/Contents/Info.plist" <<PLIST
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
<key>GCSourceRevision</key><string>$REVISION</string>
<key>GCSourceDirty</key><string>$DIRTY</string>
<key>GCBuildDate</key><string>$BUILD_DATE</string>
<key>GCSigningRequested</key><string>$SIGNING_LABEL</string>
<key>NSAccessibilityUsageDescription</key><string>GuideCursor reads controls in your chosen app to highlight them and provide directions. You remain in control of clicks.</string>
</dict></plist>
PLIST
xattr -cr "$APP"  # staged bundle only
codesign --force --sign "$SIGN_WITH" "$APP"
codesign --verify --strict --deep "$APP"
# Ad hoc signatures print an implicit requirement as a "# designated => ..." comment line.
DESIGNATED="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^#* *designated => //p')"
CDHASH="$(codesign -dvvv "$APP" 2>&1 | sed -n 's/^CDHash=//p')"

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
printf 'Source %s (uncommitted changes under macos/: %s)\n' "$REVISION" "$DIRTY"
printf 'Signed with: %s\nCDHash: %s\nDesignated requirement: %s\n' "$( [ "$SIGN_WITH" = "-" ] && echo ad-hoc || echo "$IDENTITY")" "$CDHASH" "$DESIGNATED"
if [ "$SIGN_WITH" = "-" ]; then
    echo "Note: ad hoc signature. macOS may not apply an earlier Accessibility approval to this build; if GuideCursor reports permission missing, remove its old entry under Privacy & Security → Accessibility and add this app."
fi

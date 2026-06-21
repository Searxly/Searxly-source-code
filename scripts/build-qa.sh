#!/bin/bash
#
# Searxly QA / Tester Build Script
#
# IMPORTANT FOR YOU (no paid Apple Developer subscription):
#   - You will get a perfectly usable .dmg
#   - Testers on other Macs will see a Gatekeeper warning (this is expected)
#   - The script is tuned for personal team / ad-hoc builds
#   - It will always produce a nice DMG as the main deliverable
#
# What testers will need to do (documented inside the DMG too):
#   Right-click the app → Open   (or use the included instructions)
#
# Usage:
#   chmod +x scripts/build-qa.sh
#   ./scripts/build-qa.sh
#
# Output (in dist/):
#   Searxly-QA-YYYYMMDD-HHMM.dmg   <-- give this to people
#   (plus the raw .app if they need it)
#
# The DMG contains:
#   - The app
#   - A symlink to /Applications (classic drag-to-install)
#   - QA-OPEN-INSTRUCTIONS.txt with clear steps for the Gatekeeper warning

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

SCHEME="Searxly"
CONFIGURATION="Release"
ARCHIVE_PATH="$PROJECT_DIR/build/Searxly.xcarchive"
EXPORT_PATH="$PROJECT_DIR/build/Export"
DIST_DIR="$PROJECT_DIR/dist"
TIMESTAMP=$(date +%Y%m%d-%H%M)
APP_NAME="Searxly-QA-${TIMESTAMP}.app"
DMG_NAME="Searxly-QA-${TIMESTAMP}.dmg"

echo "=== Searxly QA Build (personal / no paid Developer ID mode) ==="
echo "Project: $PROJECT_DIR"
echo "This build will produce a .dmg suitable for handing to QA testers."
echo "Testers will need to right-click → Open the first time (Gatekeeper)."
echo ""

# Clean previous
rm -rf build dist
mkdir -p build "$DIST_DIR"

echo "→ Cleaning and archiving (Release)..."
xcodebuild clean archive \
  -project Searxly.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH" \
  -quiet

echo "→ Exporting archive (development / ad-hoc signing)..."
# Using "development" method because you don't have a paid Developer ID cert.
# This is the realistic option for personal Apple ID teams.
cat > build/ExportOptions.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string> <!-- Replace with your Apple Developer Team ID before building. -->
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist build/ExportOptions.plist \
  -quiet

if [ ! -d "$EXPORT_PATH/Searxly.app" ]; then
  echo "ERROR: Expected $EXPORT_PATH/Searxly.app not found after export."
  exit 1
fi

echo "→ Copying app to dist/ ..."
cp -R "$EXPORT_PATH/Searxly.app" "$DIST_DIR/$APP_NAME"

# === Create a nice DMG (this is what you'll actually send) ===
echo "→ Creating polished DMG..."

# Temporary folder for DMG contents (so we can add symlink + instructions)
DMG_TMP="$PROJECT_DIR/build/dmg_contents"
rm -rf "$DMG_TMP"
mkdir -p "$DMG_TMP"

# Copy the app
cp -R "$DIST_DIR/$APP_NAME" "$DMG_TMP/"

# Classic "drag to Applications" symlink
ln -s /Applications "$DMG_TMP/Applications"

# Include the instructions file (very important for no-notarization builds)
cp "scripts/QA-OPEN-INSTRUCTIONS.txt" "$DMG_TMP/"

# Create the DMG
hdiutil create \
  -volname "Searxly QA Build" \
  -srcfolder "$DMG_TMP" \
  -ov \
  -format UDZO \
  "$DIST_DIR/$DMG_NAME"

# Clean temp
rm -rf "$DMG_TMP"

echo ""
echo "=== Build complete ==="
echo ""
echo "✅ Your DMG is ready here:"
echo "   $DIST_DIR/$DMG_NAME"
echo ""
echo "Give testers ONLY the .dmg file."
echo ""
echo "Inside the DMG they get:"
echo "  • The Searxly app"
echo "  • Applications folder (drag the app onto it to install)"
echo "  • QA-OPEN-INSTRUCTIONS.txt (tells them exactly how to bypass the Gatekeeper warning)"
echo ""
echo "Since you don't have a paid Developer ID, they will need to right-click → Open the first time."
echo "The instructions file inside the DMG explains it clearly."
echo ""
echo "All files are in: $DIST_DIR/"
ls -lh "$DIST_DIR/"
echo ""
echo "Tip: You can also run the standalone ./scripts/make-dmg.sh later if you just have a .app and want to re-wrap it into a fresh DMG."

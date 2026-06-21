#!/bin/bash
#
# Simple script to turn a Searxly .app into a nice distributable .dmg
# (especially useful when you don't have a paid Developer ID for notarization)
#
# Usage:
#   ./scripts/make-dmg.sh /path/to/Searxly.app
#
# Or run without arguments and it will try to find the most recent build:
#   ./scripts/make-dmg.sh
#
# It will create:
#   - A .dmg with the app + Applications symlink (easy drag install)
#   - Includes the QA-OPEN-INSTRUCTIONS.txt inside the DMG
#
# Output goes to dist/ folder.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

mkdir -p dist

# Find the .app
if [ $# -eq 1 ]; then
    APP_PATH="$1"
else
    # Try to auto-detect the latest built app
    if [ -d "build/Export/Searxly.app" ]; then
        APP_PATH="build/Export/Searxly.app"
    elif [ -d "$(find ~/Library/Developer/Xcode/DerivedData -name 'Searxly.app' -type d 2>/dev/null | head -1)" ]; then
        APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name 'Searxly.app' -type d 2>/dev/null | head -1)
    else
        echo "Usage: $0 /path/to/Searxly.app"
        echo "Or build first with Xcode / build-qa.sh so it can auto-detect."
        exit 1
    fi
fi

if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH is not a directory / not a .app bundle"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d-%H%M)
DMG_NAME="dist/Searxly-QA-${TIMESTAMP}.dmg"
TMP_DIR="build/dmg-staging"

echo "Creating DMG from: $APP_PATH"
echo "Output will be: $DMG_NAME"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Copy the app
cp -R "$APP_PATH" "$TMP_DIR/"

# Add the classic Applications symlink (users drag the app onto it)
ln -s /Applications "$TMP_DIR/Applications"

# Include the instructions file (very important for non-notarized builds)
if [ -f "scripts/QA-OPEN-INSTRUCTIONS.txt" ]; then
    cp "scripts/QA-OPEN-INSTRUCTIONS.txt" "$TMP_DIR/"
else
    echo "Warning: QA-OPEN-INSTRUCTIONS.txt not found"
fi

# Create the DMG (compressed, read-only)
hdiutil create \
    -volname "Searxly QA" \
    -srcfolder "$TMP_DIR" \
    -ov \
    -format UDZO \
    "$DMG_NAME"

rm -rf "$TMP_DIR"

echo ""
echo "✅ Done!"
echo "Your DMG is ready: $DMG_NAME"
echo ""
echo "Give this .dmg to your QA testers."
echo "Inside the DMG they will find the app + the instructions file explaining how to open it (right-click Open because no notarization)."
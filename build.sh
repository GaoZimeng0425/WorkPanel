#!/bin/bash
set -euo pipefail

SCHEME="WorkPanel"
PROJECT="WorkPanel.xcodeproj"
BUILD_DIR="build"
APP_NAME="WorkPanel"
DMG_NAME="WorkPanel"

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving..."
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$BUILD_DIR/$SCHEME.xcarchive" \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_HARDENED_RUNTIME=NO \
  | tail -1

echo "==> Exporting .app..."
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/$SCHEME.xcarchive" \
  -exportPath "$BUILD_DIR/export" \
  -exportOptionsPlist ExportOptions.plist

echo "==> Ad-hoc signing..."
codesign --force --deep --sign - "$BUILD_DIR/export/$APP_NAME.app"

echo "==> Creating DMG..."
DMG_STAGING="$BUILD_DIR/dmg_staging"
mkdir -p "$DMG_STAGING"
cp -R "$BUILD_DIR/export/$APP_NAME.app" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov -format UDZO \
  "$BUILD_DIR/$DMG_NAME.dmg"

echo "==> Done: $BUILD_DIR/$DMG_NAME.dmg"
ls -lh "$BUILD_DIR/$DMG_NAME.dmg"

# ----------------------------------------------------------------------------
# Deploy: kill the running app, replace /Applications copy, relaunch.
# The freshly exported .app is at $BUILD_DIR/export/$APP_NAME.app; we copy it
# into /Applications and open it so you can try the new build immediately.
# ----------------------------------------------------------------------------
APP_BUNDLE="$BUILD_DIR/export/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"

echo "==> Closing running $APP_NAME..."
# Graceful quit first, then force-kill any survivors. Ignore errors so a
# not-yet-running app doesn't abort the script.
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
sleep 1
pkill -x "$APP_NAME" 2>/dev/null || true

echo "==> Installing to $INSTALL_PATH..."
rm -rf "$INSTALL_PATH"
cp -R "$APP_BUNDLE" "$INSTALL_PATH"

echo "==> Launching $APP_NAME..."
open "$INSTALL_PATH"
echo "==> All done. $APP_NAME is running from /Applications."

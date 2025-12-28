#!/bin/bash
# Development install script - updates app in place to preserve TCC permissions

APP_NAME="LocalFlow"
BUILD_DIR="$(dirname "$0")/../build"
INSTALL_DIR="/Applications"

if [ ! -d "$BUILD_DIR/$APP_NAME.app" ]; then
    echo "Error: Build not found. Run build first."
    exit 1
fi

# Kill running app
pkill -9 "$APP_NAME" 2>/dev/null

# Update in place using rsync (preserves app identity better than rm+cp)
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo "Updating $APP_NAME in place..."
    rsync -a --delete "$BUILD_DIR/$APP_NAME.app/" "$INSTALL_DIR/$APP_NAME.app/"
else
    echo "Installing $APP_NAME..."
    cp -R "$BUILD_DIR/$APP_NAME.app" "$INSTALL_DIR/"
fi

echo "Done. Starting $APP_NAME..."
open "$INSTALL_DIR/$APP_NAME.app"

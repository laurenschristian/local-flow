#!/bin/bash
set -e

# Bump version in Info.plist and project.yml

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 0.2.0"
    exit 1
fi

NEW_VERSION="$1"

echo "Bumping version to $NEW_VERSION..."

# Update Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$PROJECT_DIR/LocalFlow/Info.plist"

# Increment build number
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PROJECT_DIR/LocalFlow/Info.plist")
NEW_BUILD=$((CURRENT_BUILD + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$PROJECT_DIR/LocalFlow/Info.plist"

# Update project.yml
sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$NEW_VERSION\"/" "$PROJECT_DIR/project.yml"
sed -i '' "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$NEW_BUILD\"/" "$PROJECT_DIR/project.yml"

echo "Version: $NEW_VERSION"
echo "Build: $NEW_BUILD"
echo "Done!"

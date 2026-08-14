#!/bin/zsh
# Usage: scripts/release.sh 0.9.0
# Builds, signs, zips, creates the GitHub release, and updates the brew cask.
set -euo pipefail
V="${1:?version required, e.g. 0.9.0}"
cd "$(dirname "$0")/.."

B=$(( $(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" LocalFlow/Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $V" -c "Set :CFBundleVersion $B" LocalFlow/Info.plist
sed -i '' -e "s/MARKETING_VERSION = .*/MARKETING_VERSION = $V;/" -e "s/CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $B;/" LocalFlow.xcodeproj/project.pbxproj

xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -configuration Release -derivedDataPath build build | grep -E "error|BUILD"
APP=build/Build/Products/Release/LocalFlow.app
codesign --force --deep --preserve-metadata=entitlements --sign "Apple Development: lg@mail12.me (ZRP7TYYLP8)" "$APP"

ZIP="/tmp/LocalFlow-$V.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

gh release create "v$V" "$ZIP" -R laurenschristian/local-flow -t "LocalFlow $V" --generate-notes

TAP="$HOME/Documents/GitHub/personal/homebrew-tap"
sed -i '' -e "s/version \".*\"/version \"$V\"/" -e "s/sha256 \".*\"/sha256 \"$SHA\"/" "$TAP/Casks/localflow.rb"
git -C "$TAP" commit -am "chore: localflow $V" && git -C "$TAP" push

echo "Released $V (build $B). Upgrade with: brew upgrade --cask --no-quarantine localflow"

#!/bin/zsh
# Builds a Release version of TimeTracker and installs it into /Applications.
set -e
cd "$(dirname "$0")"
pkill -x TimeTracker 2>/dev/null || true
xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -configuration Release -derivedDataPath build build -quiet
rm -rf /Applications/TimeTracker.app
cp -R build/Build/Products/Release/TimeTracker.app /Applications/
open /Applications/TimeTracker.app
echo "Installed /Applications/TimeTracker.app"

#!/bin/zsh
# Builds a Release version of TimeTracker and packages it as dist/TimeTracker.dmg
# (drag-to-Applications disk image) and dist/TimeTracker.zip.
set -e
cd "$(dirname "$0")"
VERSION=$(sed -n 's/.*MARKETING_VERSION = \([0-9.]*\);.*/\1/p' TimeTracker.xcodeproj/project.pbxproj | head -1)
APP=build/Build/Products/Release/TimeTracker.app
STAGE=build/dmg-stage

xcodebuild -project TimeTracker.xcodeproj -scheme TimeTracker -configuration Release -derivedDataPath build build -quiet

rm -rf "$STAGE" dist && mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -quiet -volname "TimeTracker" -srcfolder "$STAGE" -ov -format UDZO "dist/TimeTracker-$VERSION.dmg"
ditto -c -k --keepParent "$APP" "dist/TimeTracker-$VERSION.zip"
rm -rf "$STAGE"

echo "Created:"
ls -lh dist

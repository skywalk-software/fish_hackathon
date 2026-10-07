#!/bin/sh
# Builds build/Planetfall.app (release, ad-hoc signed) with the story file inside.
# dfrotz still comes from Homebrew: brew install frotz
set -e
cd "$(dirname "$0")/.."

[ -f Story/planetfall.z3 ] || ./scripts/fetch-story.sh
swift build -c release --product Planetfall

APP=build/Planetfall.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Planetfall" "$APP/Contents/MacOS/Planetfall"
cp Story/planetfall.z3 "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Planetfall</string>
  <key>CFBundleIdentifier</key><string>com.skywalk.planetfall</string>
  <key>CFBundleExecutable</key><string>Planetfall</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"

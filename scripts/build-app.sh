#!/bin/sh
# Builds build/Planetfall.app (release, ad-hoc signed) with the story file inside.
# dfrotz still comes from Homebrew: brew install frotz
# SWIFT_BUILD_FLAGS adds flags to `swift build` (the Homebrew formula passes --disable-sandbox).
set -e
cd "$(dirname "$0")/.."

[ -f Story/planetfall.z3 ] || ./scripts/fetch-story.sh
swift build -c release --product Planetfall $SWIFT_BUILD_FLAGS

APP=build/Planetfall.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release $SWIFT_BUILD_FLAGS --show-bin-path)/Planetfall" "$APP/Contents/MacOS/Planetfall"
cp Story/planetfall.z3 "$APP/Contents/Resources/"
cp -R Art "$APP/Contents/Resources/Art"

# AppIcon.icns from Art/AppIcon.png (1024x1024).
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Art/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Art/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Planetfall</string>
  <key>CFBundleIdentifier</key><string>com.skywalk.planetfall</string>
  <key>CFBundleExecutable</key><string>Planetfall</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Planetfall listens while you hold Option (or the mic button) so you can speak commands.</string>
</dict>
</plist>
PLIST
# Finder metadata (e.g. on images dragged into Art/) makes codesign refuse the bundle.
xattr -cr "$APP"
codesign --force --sign - "$APP"
echo "Built $APP"

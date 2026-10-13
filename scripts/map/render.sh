#!/bin/sh
# Renders planetfall-map.svg (marked with where the game starts) to PNG and PDF with headless
# Chrome, and moves the unmarked copy into Art/Map for the game.
cd "$(dirname "$0")/../../docs/map"
CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
render() {  # $1 = SVG name without extension; $2 = also make a PNG
  W=$(sed -n 's/.*<svg[^>]* width="\([0-9]*\)" height="\([0-9]*\)".*/\1/p' "$1.svg" | head -1)
  H=$(sed -n 's/.*<svg[^>]* width="\([0-9]*\)" height="\([0-9]*\)".*/\2/p' "$1.svg" | head -1)
  cat > page.html <<HTML
<!doctype html><html><head><style>@page{size:${W}px ${H}px;margin:0}html,body{margin:0;padding:0}svg{display:block}</style></head><body>
$(cat "$1.svg")
</body></html>
HTML
  if [ -n "$2" ]; then
    "$CH" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1.5 --window-size=$W,$H --screenshot="$PWD/$1.png" "file://$PWD/page.html" 2>/dev/null
  fi
  "$CH" --headless=new --disable-gpu --no-pdf-header-footer --print-to-pdf="$PWD/$1.pdf" "file://$PWD/page.html" 2>/dev/null
  rm -f page.html
}
render planetfall-map png
ls -la planetfall-map.png planetfall-map.pdf
# The game shows the unmarked SVG ("map" and "cheat: map"): it moves its own marker onto the
# player's room and hides what they haven't explored, using the data-room/data-link tags.
mkdir -p ../../Art/Map
mv planetfall-map-base.svg ../../Art/Map/planetfall-map.svg
cp planetfall-map.json ../../Art/Map/
rm -f ../../Art/Map/planetfall-map.pdf

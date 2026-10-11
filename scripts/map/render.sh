#!/bin/sh
# Renders the map SVGs to PNG and PDF with headless Chrome: planetfall-map (marked with where the
# game starts) for docs/map, and planetfall-map-base (no marker) for the game's own copy in Art/Map.
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
render planetfall-map-base
ls -la planetfall-map.png planetfall-map.pdf
# The game app shows the unmarked map (cheat: map) and places its own marker from the JSON.
mkdir -p ../../Art/Map
cp planetfall-map-base.pdf ../../Art/Map/planetfall-map.pdf
cp planetfall-map.json ../../Art/Map/
rm -f planetfall-map-base.svg planetfall-map-base.pdf

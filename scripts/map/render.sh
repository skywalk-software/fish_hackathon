#!/bin/sh
# Renders planetfall-map.svg to PNG and PDF with headless Chrome.
cd "$(dirname "$0")/../../docs/map"
W=$(sed -n 's/.*<svg[^>]* width="\([0-9]*\)" height="\([0-9]*\)".*/\1/p' planetfall-map.svg | head -1)
H=$(sed -n 's/.*<svg[^>]* width="\([0-9]*\)" height="\([0-9]*\)".*/\2/p' planetfall-map.svg | head -1)
cat > page.html <<HTML
<!doctype html><html><head><style>@page{size:${W}px ${H}px;margin:0}html,body{margin:0;padding:0}svg{display:block}</style></head><body>
$(cat planetfall-map.svg)
</body></html>
HTML
CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CH" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1.5 --window-size=$W,$H --screenshot="$PWD/planetfall-map.png" "file://$PWD/page.html" 2>/dev/null
"$CH" --headless=new --disable-gpu --no-pdf-header-footer --print-to-pdf="$PWD/planetfall-map.pdf" "file://$PWD/page.html" 2>/dev/null
ls -la planetfall-map.png planetfall-map.pdf

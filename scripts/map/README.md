# Full-map generator

Builds `docs/map/planetfall-map.{svg,png,pdf}`, the complete Planetfall map, from the game's own room definitions.

1. `python3 parse.py` reads every `<ROOM>` and its exits from the Planetfall ZIL source into `rooms-raw.json`. The source isn't openly licensed, so it isn't committed; the script clones [historicalsource/planetfall](https://github.com/historicalsource/planetfall) to `/tmp/planetfall-src` on first run (or set `PLANETFALL_SRC`). `rooms-raw.json` is committed, so this step is only needed if the parser changes.
2. `python3 draw.py` lays the rooms out and draws the SVG:
   - `POS` places each room on a grid (hand placed).
   - Exits the game works out in code are written out by hand: `special` (elevators, shuttles, the rift ladder, flooding), `RIDES` and `SHAFTS` (dashed rides), `STUBS` (refusals and loops).
   - It draws in two passes: the first measures each room's notes, the second grows the region boxes to hold them.
3. `./render.sh` turns the SVG into PNG and PDF with headless Chrome.

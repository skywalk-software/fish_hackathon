#!/bin/sh
# Downloads the compiled Planetfall story file (Release 39) into Story/.
# It isn't committed because the game isn't openly licensed.
set -e
cd "$(dirname "$0")/.."
mkdir -p Story
curl -fsSL -o Story/planetfall.z3 \
  https://raw.githubusercontent.com/historicalsource/planetfall/master/COMPILED/planetfall.z3
echo "Saved Story/planetfall.z3"

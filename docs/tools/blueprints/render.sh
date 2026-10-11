#!/usr/bin/env bash
# Regenerate the blueprint SVGs, then render each one to a PNG to look at it.
#
#   docs/tools/blueprints/render.sh [png-folder]
#
# The PNGs go to the folder you give (default: a new temporary folder). Do not
# commit them. Rendering needs Google Chrome; set CHROME to use another path.
set -euo pipefail

here="$(cd "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
out="${1:-$(mktemp -d)}"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

python3 "$here/blueprints.py"
mkdir -p "$out"
for svg in "$root"/docs/blueprints/*.svg; do
    python3 -c "import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])" "$svg"
    read -r w h < <(python3 -c 'import re, sys; m = re.search(r"viewBox=\"0 0 (\d+) (\d+)\"", open(sys.argv[1]).read()); print(m[1], m[2])' "$svg")
    png="$out/$(basename "$svg" .svg).png"
    "$chrome" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
        --screenshot="$png" --window-size="$w,$h" "file://$svg" >/dev/null 2>&1
    echo "$png  (${w}x${h}, $(wc -c <"$svg" | tr -d ' ') bytes)"
done

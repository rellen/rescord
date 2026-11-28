#!/usr/bin/env bash
# Draws the icons that cannot follow the colour scheme, from the favicon
# (ADR 0058): `favicon.ico` for a client that takes no SVG icon, and
# `apple-touch-icon.png` for a home screen, and the two icons of the
# manifest. Run it in the devenv shell, which
# has libvips, after a change to `platform/priv/static/images/favicon.svg`:
#
#   scripts/favicons.sh
set -euo pipefail

static="$(cd "$(dirname "$0")/.." && pwd)/platform/priv/static"
source="$static/images/favicon.svg"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A green between the two values of `accent`. It has a contrast of 3 to 1 or
# more on white, on `#dee1e6`, on `#202124` and on `#35363a`, which is about
# the range of a light and of a dark tab bar. An ICO has one colour for both.
ico_stroke="#298e7e"
# The home screen icon is the mark as the light scheme shows it, on white.
touch_stroke="$(grep -o '#[0-9a-f]\{6\}' "$source" | head -n 1)"
touch_ground="255 255 255"

# render STROKE SIZE FILE: the mark in one colour as a PNG of SIZE pixels.
# The rule goes after the rules of the file, so it wins over both of them.
render() {
  sed "s|</svg>|<style>g { stroke: $1; }</style></svg>|" "$source" > "$work/mark.svg"
  vips thumbnail "$work/mark.svg" "$3[compression=9,keep=none]" "$2"
}

# le VALUE BYTES: an integer as little-endian bytes.
le() {
  local i
  for ((i = 0; i < $2; i++)); do
    # The format is the escape of one byte, which is what printf writes.
    # shellcheck disable=SC2059
    printf "\\x$(printf '%02x' $((($1 >> (8 * i)) & 255)))"
  done
}

# An ICO is a header, one entry of 16 bytes for each image, and the images.
# Each image is a PNG, which every browser reads in an ICO.
sizes=(16 32 48)
for size in "${sizes[@]}"; do
  render "$ico_stroke" "$size" "$work/$size.png"
done

offset=$((6 + 16 * ${#sizes[@]}))
{
  le 0 2
  le 1 2
  le ${#sizes[@]} 2
  for size in "${sizes[@]}"; do
    bytes=$(stat -c %s "$work/$size.png")
    le "$size" 1
    le "$size" 1
    le 0 2
    le 1 2
    le 32 2
    le "$bytes" 4
    le "$offset" 4
    offset=$((offset + bytes))
  done
  for size in "${sizes[@]}"; do cat "$work/$size.png"; done
} > "$static/favicon.ico"

# iOS draws a transparent icon on black and cuts the corners itself: the
# icon is a full square of 180 pixels, with the mark in the middle of it.
render "$touch_stroke" 108 "$work/mark.png"
vips flatten "$work/mark.png" "$work/flat.png" --background "$touch_ground"
vips embed "$work/flat.png" "$static/images/apple-touch-icon.png[compression=9,keep=none]" \
  36 36 180 180 --extend background --background "$touch_ground"

# The icons of the manifest of the installed web app (issue 29): the same
# square on white, in two sizes. The mark fills 60 percent of it, inside the
# safe zone of a maskable icon, so a launcher can cut any shape.
for size in 192 512; do
  mark=$((size * 3 / 5))
  edge=$(((size - mark) / 2))
  render "$touch_stroke" "$mark" "$work/mark-$size.png"
  vips flatten "$work/mark-$size.png" "$work/flat-$size.png" --background "$touch_ground"
  vips embed "$work/flat-$size.png" "$static/images/icon-$size.png[compression=9,keep=none]" \
    "$edge" "$edge" "$size" "$size" --extend background --background "$touch_ground"
done

echo "Wrote $static/favicon.ico, $static/images/apple-touch-icon.png and the icons of the manifest"

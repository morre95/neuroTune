#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_dir="$root/design/app-icons"
res="$root/app/android/app/src/main/res"

if ! command -v magick >/dev/null; then
  echo 'ImageMagick 7 (magick) is required.' >&2
  exit 1
fi

# Legacy icons are opaque squares; adaptive foregrounds use a 108 dp canvas.
# The source is placed in the central 80 dp, keeping the mark inside 66 dp.
for entry in mdpi:48:108:80 hdpi:72:162:120 xhdpi:96:216:160 xxhdpi:144:324:240 xxxhdpi:192:432:320; do
  IFS=: read -r density legacy canvas artwork <<< "$entry"
  mkdir -p "$res/mipmap-$density" "$res/drawable-$density"
  magick "$source_dir/resonance.png" -resize "${legacy}x${legacy}" \
    -alpha off -strip "$res/mipmap-$density/ic_launcher.png"
  magick "$source_dir/resonance-foreground.png" -resize "${artwork}x${artwork}" \
    -background none -gravity center -extent "${canvas}x${canvas}" \
    -strip "$res/drawable-$density/ic_launcher_foreground.png"
done

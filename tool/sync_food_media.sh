#!/usr/bin/env bash
# Downloads the food photographs listed in tool/food_media.tsv into assets/food/.
#
# The same arrangement the exercise media uses: ~226 images the app bundles so the food library
# works with no network, git-ignored because they are not ours to redistribute (see NOTICE.md),
# and populated by this script locally and in CI.
#
# Every image is normalised to a 512x512 centre crop. The catalogue is a grid of thumbnails and
# a row of mixed aspect ratios reads as a mistake; the exercise stills are uniform for the same
# reason.
#
#   tool/sync_food_media.sh [--force]
#
# Existing files are kept unless --force is given, so a re-run costs nothing and a partly
# fetched set can be finished off.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$DIR/food_media.tsv"
DST="$DIR/../assets/food"
FORCE="${1:-}"

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }

# Wikimedia refuses a default curl User-Agent with 429 and asks for something identifiable;
# most of the image hosts here are Commons, so this is the difference between a working sync
# and two hundred rate-limit failures.
UA="myOpenGym-media-sync/1.0 (+https://github.com/DuarteSantos8/openGym) curl"

RESIZE=""
if command -v magick >/dev/null; then RESIZE="magick"
elif command -v convert >/dev/null; then RESIZE="convert"
else echo "warning: ImageMagick not found — images will be stored at their original size" >&2
fi

[ -f "$MANIFEST" ] || { echo "no manifest at $MANIFEST — run node tool/fetch_food_media.mjs first" >&2; exit 1; }

mkdir -p "$DST"
ok=0; skip=0; fail=0

# id, food, licence, creator, url, source page
while IFS=$'\t' read -r id food licence creator url source; do
  case "$id" in ''|'#'*) continue ;; esac
  [ -n "$url" ] || continue

  # The filename gen_foods.mjs already wrote into foods.json, so the app can find it.
  slug="$(printf '%s' "$food" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9]\+/-/g' -e 's/^-//' -e 's/-$//')"
  out="$DST/$id-$slug.jpg"

  if [ -f "$out" ] && [ "$FORCE" != "--force" ]; then skip=$((skip+1)); continue; fi

  tmp="$(mktemp)"
  # --retry covers the throttling a long run still runs into; the sleep keeps it from being
  # provoked in the first place.
  if ! curl -fsSL --max-time 45 --retry 3 --retry-delay 2 --retry-connrefused \
       -A "$UA" -o "$tmp" "$url"; then
    echo "  fail $id $food" >&2; rm -f "$tmp"; fail=$((fail+1)); continue
  fi
  sleep 0.4

  if [ -n "$RESIZE" ]; then
    # -auto-orient first: a phone photo whose EXIF says "rotate 90" would otherwise be cropped
    # on the wrong axis before anything reads the flag.
    if ! "$RESIZE" "$tmp" -auto-orient -resize '512x512^' -gravity center -extent 512x512 \
         -quality 82 -strip "$out" 2>/dev/null; then
      echo "  fail $id $food (not a usable image)" >&2; rm -f "$tmp" "$out"; fail=$((fail+1)); continue
    fi
  else
    cp "$tmp" "$out"
  fi
  rm -f "$tmp"
  ok=$((ok+1))
done < "$MANIFEST"

echo "assets/food: $ok fetched · $skip already present · $fail failed · $(find "$DST" -name '*.jpg' | wc -l) files · $(du -sh "$DST" | cut -f1)"

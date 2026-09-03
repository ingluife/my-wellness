#!/usr/bin/env bash
# Copies the exercise media out of the openGym checkout into assets/.
#
# The mobile flavor of openGym pulls these off a CDN; My Wellness bundles them so the library
# works with no network at all. That is ~137 MB, so the two directories are git-ignored and
# this script is what populates them — locally and in CI.
set -euo pipefail

SRC="${1:-$(dirname "$0")/../../openGym/media}"
DST="$(dirname "$0")/../assets"

[ -d "$SRC/img" ] && [ -d "$SRC/gif" ] || { echo "no media at $SRC — run openGym/scripts/fetch-media.sh first" >&2; exit 1; }

mkdir -p "$DST/img" "$DST/gif"
rsync -a --delete "$SRC/img/" "$DST/img/"
rsync -a --delete "$SRC/gif/" "$DST/gif/"

echo "img: $(find "$DST/img" -type f | wc -l) files · gif: $(find "$DST/gif" -type f | wc -l) files · $(du -sh "$DST/img" "$DST/gif" | awk '{s=$1} END {print}') "
du -sh "$DST/img" "$DST/gif"

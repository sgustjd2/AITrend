#!/bin/bash
# Normalize the JSON date to the target encoded in its dated input filename,
# then render only the matching daily carousel.
set -euo pipefail
if [ "$#" -ne 2 ]; then
  echo "Usage: render-ai-trend-card.sh INPUT.json OUTPUT.png" >&2
  exit 2
fi
INPUT=$1
OUTPUT=$2
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  SOURCE_DIR="$(cd -P -- "$(dirname -- "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" = /* ]] || SOURCE="$SOURCE_DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P -- "$(dirname -- "$SOURCE")" && pwd)"
REPO="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
WORKSPACE="$(dirname "$REPO")"
RENDER="$WORKSPACE/team/scripts/render-ai-trend-card.py"
BASE=$(basename "$INPUT")
TARGET=${BASE%-ai-trend-card.json}
if [[ ! "$TARGET" =~ ^20[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "Input filename must be YYYY-MM-DD-ai-trend-card.json: $BASE" >&2
  exit 2
fi
if [[ "$(basename "$OUTPUT")" != "$TARGET-ai-storybook-article.png" ]]; then
  echo "Output filename must match input date $TARGET" >&2
  exit 2
fi
if ! jq -e . "$INPUT" >/dev/null 2>&1; then
  echo "Card JSON is invalid: $INPUT" >&2
  exit 1
fi
TEMP="${INPUT}.tmp.$$"
trap 'rm -f "$TEMP"' EXIT
jq --arg target "$TARGET" '.date = $target' "$INPUT" > "$TEMP"
mv "$TEMP" "$INPUT"
trap - EXIT
python3 "$RENDER" "$INPUT" --output "$OUTPUT"

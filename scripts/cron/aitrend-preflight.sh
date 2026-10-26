#!/bin/bash
# Read-only preflight for the daily AI trend job.
set -u
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
DESIGN="$WORKSPACE/team/company-standards/design.md"
DAY=$(TZ=Asia/Seoul date -v-1d '+%Y-%m-%d' 2>/dev/null || date -d 'yesterday' '+%Y-%m-%d' 2>/dev/null || true)
echo "Preflight $(TZ=Asia/Seoul date '+%Y-%m-%d %H:%M KST'); target=$DAY"
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  dirty=$(git -C "$REPO" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  echo "REPO: ok; local changes=$dirty (preflight read-only; date report/card may be committed)"
else
  echo "REPO: FAIL; repository unavailable"
fi
echo "THREADS: 공개 웹 검색만 사용; 로그인 세션/브라우저 접근 안 함"
if curl -fsS --max-time 2 http://127.0.0.1:11434/api/tags >/dev/null; then echo "OLLAMA: ok"; else echo "OLLAMA: FAIL; local model API unavailable"; fi
if [ -s "$RENDER" ] && python3 -c 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); compile(p.read_text(encoding="utf-8"), str(p), "exec")' "$RENDER" 2>/dev/null; then
  echo "CARD_RENDERER: ok (file exists; syntax valid)"
else
  echo "CARD_RENDERER: FAIL; missing file or Python syntax error ($RENDER)"
fi
[ -s "$DESIGN" ] && echo "DESIGN_STANDARD: ok" || echo "DESIGN_STANDARD: FAIL; $DESIGN missing"
[ -s "$HOME/.hermes/skills/ai-trend-daily-meeting/SKILL.md" ] && echo "SKILL: ok" || echo "SKILL: FAIL"

# Skip duplicate local reports only after checking the repository's actual
# YYYY-MM-DD-ai-storybook-article.{png,svg} naming and cache attachment files.
if [[ "$DAY" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  YEAR=${DAY:0:4}
  MONTH=${DAY:5:2}
  OUTDIR="$REPO/$YEAR/$MONTH"
  REPORT="$OUTDIR/$DAY-ai-trend.md"
  CARD_JSON="$OUTDIR/$DAY-ai-trend-card.json"
  SOURCE_RECEIPT="$OUTDIR/$DAY-ai-trend.sources.json"
  CARD_BASE="$REPO/previews/$DAY-ai-storybook-article"
  CACHE_BASE="$HOME/.hermes/cache/documents/ai-trend-$DAY"
  complete=true

  [ -s "$REPORT" ] || complete=false
  [ -s "$CARD_JSON" ] || complete=false
  [ -s "$SOURCE_RECEIPT" ] || complete=false
  if [ "$complete" = true ]; then
    head -1 "$REPORT" | grep -Fq "$DAY" || complete=false
    grep -Fq '## 카드뉴스 산출물' "$REPORT" || complete=false
    jq -e --arg day "$DAY" '.date == $day and (.issues | length > 0)' "$CARD_JSON" >/dev/null 2>&1 || complete=false
    jq -e --arg day "$DAY" '
      .schemaVersion == 3 and .targetDate == $day and
      (. as $doc | ["threads", "hf_vlm", "vision_models", "geeknews", "toss_tech", "inpa", "goddaehee", "github_projects"] |
        all(.[]; . as $key | any($doc.coverage[]?; .key == $key and .status == "checked")))
    ' "$SOURCE_RECEIPT" >/dev/null 2>&1 || complete=false

    png_count=0
    svg_count=0
    for png in "$CARD_BASE"*.png; do
      [ -f "$png" ] || continue
      png_count=$((png_count + 1))
      svg="${png%.png}.svg"
      [ -s "$svg" ] || complete=false
      if command -v sips >/dev/null 2>&1; then
        dimensions=$(sips -g pixelWidth -g pixelHeight "$png" 2>/dev/null | awk '/pixelWidth/{w=$2}/pixelHeight/{h=$2}END{if(w&&h)print w"x"h}')
        [ "$dimensions" = '1440x1800' ] || complete=false
      else
        complete=false
      fi
      suffix=${png#"$CARD_BASE"}
      cached_png="$CACHE_BASE$suffix"
      [ -s "$cached_png" ] && cmp -s "$png" "$cached_png" || complete=false
    done
    for svg in "$CARD_BASE"*.svg; do
      [ -f "$svg" ] || continue
      svg_count=$((svg_count + 1))
    done
    [ "$png_count" -gt 0 ] && [ "$png_count" -eq "$svg_count" ] || complete=false
    grep -Fq "previews/$DAY-ai-storybook-article.png" "$REPORT" || complete=false

    json_mtime=$(stat -f '%m' "$CARD_JSON" 2>/dev/null || echo 0)
    renderer_mtime=$(stat -f '%m' "$RENDER" 2>/dev/null || echo 0)
    newest_visual_source_mtime=$json_mtime
    [ "$renderer_mtime" -gt "$newest_visual_source_mtime" ] && newest_visual_source_mtime=$renderer_mtime
    for artifact in "$REPORT" "$CACHE_BASE.md"; do
      [ -f "$artifact" ] || { complete=false; continue; }
      artifact_mtime=$(stat -f '%m' "$artifact" 2>/dev/null || echo 0)
      [ "$artifact_mtime" -ge "$json_mtime" ] || complete=false
    done
    for artifact in "$CARD_BASE"*.png "$CARD_BASE"*.svg "$CACHE_BASE"*.png; do
      [ -f "$artifact" ] || continue
      artifact_mtime=$(stat -f '%m' "$artifact" 2>/dev/null || echo 0)
      [ "$artifact_mtime" -ge "$newest_visual_source_mtime" ] || complete=false
    done
    [ -s "$CACHE_BASE.png" ] || complete=false
    cmp -s "$CARD_BASE.png" "$CACHE_BASE.png" || complete=false
    [ -s "$CACHE_BASE.md" ] && cmp -s "$REPORT" "$CACHE_BASE.md" || complete=false
  fi

  if [ "$complete" = true ]; then
    echo "DUPLICATE_SKIP=1; verified report and $png_count-card PNG/SVG deck already exist for $DAY"
    echo '{"wakeAgent": false}'
  else
    echo "DUPLICATE_SKIP=0; target report or required deliverables are missing/incomplete"
    echo '{"wakeAgent": true}'
  fi
fi

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP_DIR="$(mktemp -d)"
SITE_DIR="$TMP_DIR/www"
mkdir -p \
  "$SITE_DIR/collections/newsroom/items/001" \
  "$SITE_DIR/collections/newsroom/items/002" \
  "$SITE_DIR/collections/transformation-thread/items/001" \
  "$SITE_DIR/collections/transformation-thread/items/002" \
  "$SITE_DIR/collections/transformation-thread/items/003"

cat >"$SITE_DIR/collections/newsroom/collection.json" <<'JSON'
{
  "id": "newsroom",
  "mode": "publication",
  "sectionHref": "/#newsroom",
  "labels": {
    "itemPrefix": "NR"
  },
  "selection": {
    "strategy": "latest",
    "visibleItems": 1,
    "timezone": "America/Los_Angeles",
    "outputFile": "generated/selection.json"
  }
}
JSON

for item in 001 002; do
  cat >"$SITE_DIR/collections/newsroom/items/$item/title.md" <<MD
News item $item
MD
  cat >"$SITE_DIR/collections/newsroom/items/$item/excerpt.md" <<MD
Excerpt $item
MD
  cat >"$SITE_DIR/collections/newsroom/items/$item/full-article.md" <<MD
# News item $item

Body $item
MD
done

cat >"$SITE_DIR/collections/newsroom/items/001/meta.json" <<'JSON'
{
  "category": "News",
  "status": "Published",
  "publishDate": "2026-07-18",
  "dateFirstDisplayed": "2026-07-18",
  "displayAfter": []
}
JSON
cat >"$SITE_DIR/collections/newsroom/items/002/meta.json" <<'JSON'
{
  "category": "News",
  "status": "Published",
  "publishDate": "2026-07-20",
  "dateFirstDisplayed": null,
  "displayAfter": []
}
JSON

cat >"$SITE_DIR/collections/transformation-thread/collection.json" <<'JSON'
{
  "id": "transformation-thread",
  "mode": "publication",
  "sectionHref": "/#blog",
  "labels": {
    "itemPrefix": "TT"
  },
  "selection": {
    "strategy": "weekday-week-of-month",
    "visibleItems": 2,
    "timezone": "America/New_York",
    "outputFile": "generated/selection.json"
  }
}
JSON

for item in 001 002 003; do
  cat >"$SITE_DIR/collections/transformation-thread/items/$item/title.md" <<MD
Thread item $item
MD
  cat >"$SITE_DIR/collections/transformation-thread/items/$item/excerpt.md" <<MD
Excerpt $item
MD
  cat >"$SITE_DIR/collections/transformation-thread/items/$item/full-article.md" <<MD
# Thread item $item

Body $item
MD
done

cat >"$SITE_DIR/collections/transformation-thread/items/001/meta.json" <<'JSON'
{
  "slot": 1,
  "category": "Systems",
  "status": "Draft",
  "dateFirstDisplayed": "2026-07-01",
  "displayAfter": []
}
JSON
cat >"$SITE_DIR/collections/transformation-thread/items/002/meta.json" <<'JSON'
{
  "slot": 2,
  "category": "Systems",
  "status": "Draft",
  "dateFirstDisplayed": "2026-07-01",
  "displayAfter": []
}
JSON
cat >"$SITE_DIR/collections/transformation-thread/items/003/meta.json" <<'JSON'
{
  "slot": 3,
  "category": "Systems",
  "status": "Draft",
  "dateFirstDisplayed": "2026-07-01",
  "displayAfter": []
}
JSON

"$ROOT/pm-materialize-publication-collections" --site-dir "$SITE_DIR" --date 2026-07-20 >/dev/null

python3 - "$SITE_DIR" <<'PY'
import json
import sys
from pathlib import Path

site = Path(sys.argv[1])
newsroom = json.loads((site / "collections/newsroom/generated/selection.json").read_text())
thread = json.loads((site / "collections/transformation-thread/generated/selection.json").read_text())
news_meta = json.loads((site / "collections/newsroom/items/002/meta.json").read_text())

assert newsroom["collection"] == "newsroom"
assert newsroom["selection_date"] == "2026-07-20"
assert [item["slug"] for item in newsroom["visibleItems"]] == ["nr-002"]
assert news_meta["dateFirstDisplayed"] == "2026-07-20"

assert thread["collection"] == "transformation-thread"
assert thread["selection_date"] == "2026-07-20"
assert [item["slug"] for item in thread["visibleItems"]] == ["tt-001", "tt-002"]
assert thread["active_slot"] == 1
assert thread["week_of_month"] == 3
PY

grep -Fq 'static_prepare_publication_collections' "$ROOT/pm-deploy-static"
grep -Fq 'pm-index-publication-collections' "$ROOT/pm-helpers-static"

printf 'PASS: legacy publication materializer remains available outside the runtime-selection deploy contract\n'

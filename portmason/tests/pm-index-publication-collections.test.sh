#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
COLLECTION_DIR="$TMP_DIR/site/collections/daily"
mkdir -p "$COLLECTION_DIR/items/001"

cat >"$COLLECTION_DIR/collection.json" <<'JSON'
{
  "id": "daily",
  "mode": "publication",
  "dataFile": "items/index.json",
  "sectionHref": "/#daily",
  "labels": { "itemPrefix": "DAILY" },
  "selection": {
    "strategy": "weekday-week-of-month",
    "visibleItems": 1,
    "timezone": "America/Los_Angeles"
  }
}
JSON
cat >"$COLLECTION_DIR/items/001/meta.json" <<'JSON'
{
  "slot": 1,
  "category": "Guidance",
  "status": "Published",
  "publishDate": null,
  "dateFirstDisplayed": null,
  "displayAfter": [],
  "url": "https://example.test/article"
}
JSON
printf 'A useful title\n' >"$COLLECTION_DIR/items/001/title.md"
printf 'A useful summary.\n' >"$COLLECTION_DIR/items/001/excerpt.md"
printf 'A complete article.\n' >"$COLLECTION_DIR/items/001/full-article.md"

"$ROOT/pm-index-publication-collections" --site-dir "$TMP_DIR/site" >/dev/null

[[ "$(stat -c '%a' "$COLLECTION_DIR/items/index.json")" == "644" ]]
chmod 600 "$COLLECTION_DIR/items/index.json"
"$ROOT/pm-index-publication-collections" --site-dir "$TMP_DIR/site" >/dev/null
[[ "$(stat -c '%a' "$COLLECTION_DIR/items/index.json")" == "644" ]]

python3 - "$COLLECTION_DIR/items/index.json" <<'PY'
import json
import sys
from pathlib import Path

items = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert len(items) == 1
assert items[0]["id"] == 1
assert items[0]["slot"] == 1
assert items[0]["title"] == "A useful title"
assert items[0]["title_md"] == "items/001/title.md"
assert items[0]["url"] == "https://example.test/article"
PY

printf 'PASS: publication filesystem index is browser-readable\n'

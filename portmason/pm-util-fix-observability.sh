#!/usr/bin/env bash

set -euo pipefail

echo "Replacing known bad telemetry replacements..."

find . -type f \
    ! -path "*/.git/*" \
    ! -path "*/node_modules/*" \
    ! -path "*/.venv/*" \
    ! -path "*/venv/*" \
    ! -path "*/dist/*" \
    ! -path "*/build/*" \
| while read -r file; do

    python3 - "$file" <<'PY'
import sys
from pathlib import Path

f = Path(sys.argv[1])

try:
    text = f.read_text(encoding="utf-8")
except Exception:
    sys.exit(0)

original = text

replacements = {
    "prj_observability": "prj_observability",
    "br_observability": "br_observability",
    "observabilitobservabilitobservability_db": "observabilitobservabilitobservabilitobservability_db",
    "observabilitobservabilitobservability_app": "observabilitobservabilitobservabilitobservability_app",
    "pm_observability_": "pm_observability_",
    "Neon observability database": "Neon observability database",
    "Neon observability role": "Neon observability role",
    "Neon observability log collector": "Neon observability log collector",
    "Neon observability logs unavailable": "Neon observability logs unavailable",
    "PASS: Neon observability role lifecycle": "PASS: Neon observability role lifecycle",
    "'observability,web,app,worker,jobs,proxy'": "'observability,web,app,worker,jobs,proxy'",
    '"role":{"name":"observabilityobservabilitobservabilitobservability_app"}': '"role":{"name":"observabilitobservabilitobservability_app"}',
    '"database":{"name":"observabilitobservabilitobservabilitobservability_db","owner_name":"observabilitobservabilitobservabilitobservability_app"}':
        '"database":{"name":"observability_db","owner_name":"observability_app"}',
    "://\\-log-ingest:8080":
        "://observability-log-ingest:8080",
}

for old, new in replacements.items():
    text = text.replace(old, new)

if text != original:
    f.write_text(text, encoding="utf-8")
    print(f"UPDATED {f}")
PY

done

echo
echo "Done."

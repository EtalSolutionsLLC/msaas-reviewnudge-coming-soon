#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
ENTRY="$ROOT/pm-observability-status"

bash -n "$ENTRY"
grep -Fq '. "${PORTMASON_SHARE}/pm-helpers-observability" --read-only' "$ENTRY"
grep -Fq 'pm_observability_local_compose ps "${services[@]}"' "$ENTRY"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
cp "$ENTRY" "$tmp/pm-observability-status"
cat >"$tmp/pm-helpers-observability" <<'SH'
die() {
    printf '%s\n' "$*" >&2
    exit 2
}
observability_is_true() {
    [[ "${1:-}" == true ]]
}
pm_observability_local_compose() {
    printf '%s\n' "$*" >"${TRACE:?}"
}
SH
chmod +x "$tmp/pm-observability-status"
TRACE="$tmp/trace" PORTMASON_SHARE="$tmp" OBSERVABILITY_STORE_PLATFORM_CODE=local \
    "$tmp/pm-observability-status"
grep -Fxq 'ps observability-store observability-collector' "$tmp/trace"

TRACE="$tmp/trace" PORTMASON_SHARE="$tmp" OBSERVABILITY_STORE_PLATFORM_CODE=local \
    OBSERVABILITY_DASHBOARD_ENABLED=true "$tmp/pm-observability-status"
grep -Fxq 'ps observability-store observability-collector observability-dashboard' "$tmp/trace"

echo 'pm-observability-status compatibility test passed'

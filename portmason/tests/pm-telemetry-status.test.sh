#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
ENTRY="$ROOT/pm-telemetry-status"

bash -n "$ENTRY"
grep -Fq '. "${PORTMASON_SHARE}/pm-helpers-telemetry" --read-only' "$ENTRY"
grep -Fq 'pm_telemetry_local_compose ps "${services[@]}"' "$ENTRY"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
cp "$ENTRY" "$tmp/pm-telemetry-status"
cat >"$tmp/pm-helpers-telemetry" <<'SH'
die() {
    printf '%s\n' "$*" >&2
    exit 2
}
telemetry_is_true() {
    [[ "${1:-}" == true ]]
}
pm_telemetry_local_compose() {
    printf '%s\n' "$*" >"${TRACE:?}"
}
SH
chmod +x "$tmp/pm-telemetry-status"
TRACE="$tmp/trace" PORTMASON_SHARE="$tmp" TELEMETRY_STORE_PLATFORM_CODE=local \
    "$tmp/pm-telemetry-status"
grep -Fxq 'ps telemetry-store telemetry-collector' "$tmp/trace"

TRACE="$tmp/trace" PORTMASON_SHARE="$tmp" TELEMETRY_STORE_PLATFORM_CODE=local \
    TELEMETRY_DASHBOARD_ENABLED=true "$tmp/pm-telemetry-status"
grep -Fxq 'ps telemetry-store telemetry-collector telemetry-dashboard' "$tmp/trace"

echo 'pm-telemetry-status compatibility test passed'

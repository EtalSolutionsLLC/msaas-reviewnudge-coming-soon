#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PORTMASON_DIR="$(cd -- "${TEST_DIR}/.." && pwd -P)"
log() { :; }
warn() { :; }
die() { printf 'ERROR: %s\n' "${1:-unknown}" >&2; return "${2:-1}"; }
# shellcheck disable=SC1091
. "${PORTMASON_DIR}/pm-secret-registry"

runtime_keys="$(pm_secret_registry_keys_for_classification runtime)"
control_keys="$(pm_secret_registry_keys_for_classification control-plane)"
grep -Fxq PM_SUPPORT_CHANNEL_BOT_TOKEN <<<"$runtime_keys"
grep -Fxq DB_PASSWORD <<<"$runtime_keys"
grep -Fxq DB_API_KEY <<<"$control_keys"
if grep -Fxq DB_API_KEY <<<"$runtime_keys"; then
    printf 'FAIL: control-plane key appeared in runtime registry\n' >&2
    exit 1
fi
printf 'PASS: legacy secret-registry facade delegates to PM Configuration Manager\n'

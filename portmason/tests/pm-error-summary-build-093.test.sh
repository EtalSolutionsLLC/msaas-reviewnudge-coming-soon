#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/test-summary.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
PORTMASON_SHARE="$HERE"
DEPLOY_ENV=dev
SCRIPT_DIR="$TMP"
PROJECT_ROOT="$TMP"
ENV_FILE="$TMP/.env"
: > "$TMP/.env"
. "$HERE/pm-helpers" --minimal
pm_error_summary_reset
log ERROR "first failure" "phase=configuration" "rc=2"
log CRITICAL "second failure" "phase=deploy" "rc=7"
pm_error_summary_print
pm_error_summary_print
SCRIPT
chmod +x "$TMP/test-summary.sh"

output="$($TMP/test-summary.sh 2>&1 || true)"
grep -Fq 'ERROR SUMMARY (2)' <<<"$output"
grep -Fq '1. [ERROR] first failure phase=configuration rc=2' <<<"$output"
grep -Fq '2. [CRITICAL] second failure phase=deploy rc=7' <<<"$output"
[[ "$(grep -Fc 'ERROR SUMMARY (' <<<"$output")" -eq 1 ]]

# Aggregate preflight details are recorded for the final summary rather than
# emitted as a noisy stream of ERROR lines during validation.
grep -Fq 'pm_error_record ERROR "pm-preflight: [$category] $key: $message"' \
    "$HERE/pm-helpers-db"
grep -Fq 'PM_SETUP_HANDLED_FAILURE=1' "$HERE/pm-setup"
grep -Fq 'pm_error_summary_print' "$HERE/pm-setup"

printf 'pm-error-summary-build-093: PASS\n'

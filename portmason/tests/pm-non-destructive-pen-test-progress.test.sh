#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
script="$root/pm-non-destructive-pen-test"

bash -n "$script"

grep -Fq 'ZAP_STARTUP_TIMEOUT_SECONDS:=120' "$script"
grep -Fq 'ZAP_TOTAL_TIMEOUT_SECONDS:=600' "$script"
grep -Fq 'ZAP_HEARTBEAT_SECONDS:=15' "$script"
grep -Fq 'removing stale ZAP scanner containers' "$script"
grep -Fq 'label=com.docker.compose.project=pentest-${STACK}' "$script"
grep -Fq 'ZAP scan heartbeat' "$script"
grep -Fq 'ZAP scan timed out' "$script"
grep -Fq 'docker top "$container_name" -eo pid,args' "$script"
grep -Fq -- '--name "$ZAP_CONTAINER_NAME"' "$script"
grep -Fq -- '-z "-silent"' "$script"
grep -Fq 'docker rm -f "$ZAP_CONTAINER_NAME"' "$script"
grep -Fq 'ZAP HTML report was not produced' "$script"
grep -Fq 'ZAP JSON report was not produced' "$script"
grep -Fq 'result="warnings"' "$script"
grep -Fq '"ZAP scan complete"' "$script"
grep -Fq 'exit "$scan_rc"' "$script"

printf 'PASS: non-destructive penetration test has bounded progress and cleanup\n'

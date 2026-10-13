#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bash -n "$HERE/pm-setup"

grep -Fq \
    'trap pm_setup_exit EXIT' \
    "$HERE/pm-setup"

grep -Fq \
    'Portmason shell source syntax validation failed' \
    "$HERE/pm-setup"

if grep -Fq \
    'pm_setup_source_module_once "$module" optional "$@" || true' \
    "$HERE/pm-setup"; then

    printf '%s\n' \
        'pm-setup still suppresses workflow-module failures' >&2
    exit 1
fi

cat > "$TMP/fatal-summary.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail

PORTMASON_SHARE="$HERE"
PORTMASON_PROJECT_ROOT="$TMP"
DEPLOY_ENV=dev
SCRIPT_DIR="$TMP"
PROJECT_ROOT="$TMP"
ENV_FILE="$TMP/.env"

: > "$TMP/.env"

. "$HERE/pm-helpers" --read-only

pm_error_summary_reset

summary_on_exit() {
    local rc="\$?"

    trap - EXIT
    set +e

    pm_error_summary_print

    return "\$rc"
}

trap summary_on_exit EXIT

fatal_error "synthetic module syntax failure" 23
SCRIPT

chmod +x "$TMP/fatal-summary.sh"

set +e
output="$("$TMP/fatal-summary.sh" 2>&1)"
rc=$?
set -e

[[ "$rc" -eq 23 ]]

grep -Fq \
    'ERROR SUMMARY (1)' \
    <<<"$output"

grep -Fq \
    '[ERROR] synthetic module syntax failure exit_code=23' \
    <<<"$output"

[[ "$(grep -Fc 'ERROR SUMMARY (' <<<"$output")" -eq 1 ]]

printf '%s\n' \
    'pm-error-summary-module-failure: PASS'

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SETUP="${ROOT}/pm-setup"
HELPERS_DB="${ROOT}/pm-helpers-db"

grep -Fq 'hook_file="${MGT_SCRIPTS:-}/setup"' "$SETUP"
grep -Fq 'runtime_file="${PORTMASON_SHARE}/pm-deploy-${RUNTIME_CODE}"' "$SETUP"

hook_block="$(
    sed -n '/^pm_setup_run_application_phase()/,/^}/p' "$SETUP"
)"

if grep -Eq '^[[:space:]]*return 0[[:space:]]*$' <<<"$hook_block"; then
    printf 'application phase still returns before normal deployment\n' >&2
    exit 1
fi

grep -Fq '.role != "inbound-init"' "$HELPERS_DB"
grep -Fq '.role != "proxy"' "$HELPERS_DB"

bash -n "$SETUP"
bash -n "$HELPERS_DB"

printf 'PASS: project hook continues into Portmason deployment lifecycle\n'

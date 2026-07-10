#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PORTMASON_DIR="$(cd -- "${TEST_DIR}/.." && pwd -P)"

setup_file="${PORTMASON_DIR}/pm-setup"
helpers_db="${PORTMASON_DIR}/pm-helpers-db"

grep -Fq 'pm-config-manager' "$helpers_db"
grep -Fq 'phase=configuration' "$setup_file"
grep -Fq 'pm_config_manager_apply' "$setup_file"
grep -Fq 'pm_config_manager_prepare preflight' "$helpers_db"

config_line="$(grep -n 'pm_config_manager_apply' "$setup_file" | head -n1 | cut -d: -f1)"
db_deploy_line="$(grep -n 'pm_db_run_deploy' "$setup_file" | tail -n1 | cut -d: -f1)"
[[ "$config_line" -lt "$db_deploy_line" ]] || {
    printf 'FAIL: configuration phase must precede database deployment\n' >&2
    exit 1
}

printf 'PASS: pm-setup runs PM Configuration Manager before database/application deployment\n'

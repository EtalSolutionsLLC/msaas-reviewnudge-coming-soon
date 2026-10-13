#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PORTMASON_SHARE="$(cd -- "${TEST_DIR}/.." && pwd -P)"
export PORTMASON_SHARE

die() {
    printf '%s\n' "$1" >&2
    exit "${2:-1}"
}

# shellcheck disable=SC1090
. "${PORTMASON_SHARE}/pm-helpers-postgres"

ARGS_FILE="$(mktemp)"
trap 'rm -f "$ARGS_FILE"' EXIT

db_rt() {
    printf '%s\n' "$@" >"$ARGS_FILE"
    printf 'psql output\n'
}

output="$(pm_db_postgres_run_sql 'SELECT 1;')"
[[ "$output" == 'psql output' ]]
grep -Fxq -- '--command' "$ARGS_FILE"
grep -Fxq -- 'SELECT 1;' "$ARGS_FILE"

output="$(pm_db_postgres_run_sql 'SELECT 1;' json)"
[[ "$output" == 'psql output' ]]
grep -Fxq -- '--command' "$ARGS_FILE"
grep -Fxq -- 'SELECT 1;' "$ARGS_FILE"

if ( pm_db_postgres_run_sql 'SELECT 1' json extra ) >/dev/null 2>&1; then
    printf 'Expected extra arguments to fail\n' >&2
    exit 1
fi

for bridge in \
    "${PORTMASON_SHARE}/pm-db-bridge-postgres-local" \
    "${PORTMASON_SHARE}/pm-db-bridge-postgres-neon" \
    "${PORTMASON_SHARE}/pm-db-bridge-postgres-gcp" \
    "${PORTMASON_SHARE}/pm-db-bridge-postgres-azure"; do
    bash -n "$bridge"
    grep -Fq 'pm-run-sql()' "$bridge"
done

if grep -Fq 'pm_db_postgres_sql_returns_rows' "${PORTMASON_SHARE}/pm-helpers-postgres"; then
    printf 'SQL row-detection heuristic still exists\n' >&2
    exit 1
fi

if grep -Fq 'json_agg(row_to_json(pm_run_sql_result))' "${PORTMASON_SHARE}/pm-helpers-postgres"; then
    printf 'SQL JSON wrapper still exists\n' >&2
    exit 1
fi

printf 'PASS: pm-run-sql thin psql wrapper contract\n'

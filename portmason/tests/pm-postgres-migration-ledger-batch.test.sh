#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT INT TERM

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_count() {
    local expected="${1:?expected count required}" pattern="${2:?pattern required}" file="${3:?file required}"
    local actual
    actual="$(grep -Fc -- "$pattern" "$file" || true)"
    [[ "$actual" == "$expected" ]] || fail "expected $expected occurrences of '$pattern', found $actual"
}

export PORTMASON_SHARE="$ROOT"
export SCRIPT_DIR="$TMP/project"
mkdir -p "$SCRIPT_DIR/db/migrations"

for version in 001 002 003; do
    printf 'SELECT %s;\n' "$version" > "$SCRIPT_DIR/db/migrations/${version}_test.sql"
done

checksum_001="$(sha256sum "$SCRIPT_DIR/db/migrations/001_test.sql" | awk '{print $1}')"
calls="$TMP/db-rt-calls.txt"
sql="$TMP/db-rt-sql.txt"
logs="$TMP/logs.txt"
: >"$calls"
: >"$sql"
: >"$logs"

log() { printf '%s\n' "$*" >>"$logs"; }
die() { printf 'DIE: %s\n' "$*" >&2; exit "${2:-1}"; }
pm_load_generated_environment() { :; }

db_rt() {
    local arg has_file=0 joined
    printf '%q ' "$@" >>"$calls"
    printf '\n' >>"$calls"
    joined="$(printf '%s ' "$@")"
    for arg in "$@"; do
        [[ "$arg" == '--file=-' ]] && has_file=1
    done
    if [[ "$joined" == *'SELECT version, checksum_sha256'* ]]; then
        printf '001_test.sql\t%s\n' "$checksum_001"
        return 0
    fi
    if ((has_file)); then
        cat >>"$sql"
        printf '\n-- CALL END --\n' >>"$sql"
    fi
}

# Source the provider without triggering main.
# shellcheck disable=SC1090
. "$ROOT/pm-deploy-postgres"

pm_postgres_apply_migrations

assert_count 1 'SELECT version, checksum_sha256' "$calls"
assert_count 0 "WHERE version = :'version'" "$sql"
assert_count 1 'SELECT 002;' "$sql"
assert_count 1 'SELECT 003;' "$sql"
assert_count 2 "VALUES (:'version', :'checksum')" "$sql"
assert_count 1 'migration already applied' "$logs"
assert_count 1 'migration applied version=002_test.sql' "$logs"
assert_count 1 'migration applied version=003_test.sql' "$logs"

applied_order="$(grep -E '^SELECT 00[23];$' "$sql" | paste -sd ' ' -)"
[[ "$applied_order" == 'SELECT 002; SELECT 003;' ]] \
    || fail "missing migrations were not applied in numbered order: $applied_order"

printf 'PASS: PostgreSQL migration ledger is fetched once and missing migrations retain numbered order\n'

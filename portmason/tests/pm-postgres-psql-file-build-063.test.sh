#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_contains() { grep -Fq -- "$2" "$1" || fail "expected '$2' in $1"; }
assert_not_contains() { ! grep -Fq -- "$2" "$1" || fail "did not expect '$2' in $1"; }

export PORTMASON_SHARE="$ROOT"
export SCRIPT_DIR="$TMP/project"
export PROJECT_ROOT="$SCRIPT_DIR"
export ENV_FILE="$SCRIPT_DIR/.env"
mkdir -p "$SCRIPT_DIR/db/migrations"
cat > "${ENV_FILE}.generated" <<'ENV'
DB_PROVIDER=postgres
DB_PLATFORM=local
DB_PROVIDER_PLATFORM_CODE=postgres-local
DB_HOST=db
DB_PORT=5432
DB_NAME=generated_db
DB_USER=generated_user
DB_PASSWORD=generated_password
DB_ADMIN_USER=postgres
DB_ADMIN_PASSWORD=generated_admin_password
DB_ADMIN_DATABASE=postgres
DB_EXTENSIONS=pgcrypto
DEPLOY_ENV=dev
ENV
cat > "$SCRIPT_DIR/db/migrations/001_test.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS public.build_063_test(id integer PRIMARY KEY);
SQL

log() { :; }
die() { printf 'DIE: %s\n' "$*" >&2; exit "${2:-1}"; }
pm_db_call_optional() { return 0; }

DB_RT_CALLS="$TMP/db-rt-calls.txt"
DB_RT_SQL="$TMP/db-rt-sql.txt"
: >"$DB_RT_CALLS"
: >"$DB_RT_SQL"

db_rt() {
    local arg has_file=0
    printf '%q ' "$@" >>"$DB_RT_CALLS"
    printf '\n' >>"$DB_RT_CALLS"
    for arg in "$@"; do
        [[ "$arg" == '--file=-' ]] && has_file=1
        if [[ "$arg" == --command=* && "$arg" == *":'"* ]]; then
            fail "psql variable interpolation was placed in --command: $arg"
        fi
        if [[ "$arg" == --command=* && "$arg" == *'\\gexec'* ]]; then
            fail "\\gexec was placed in --command: $arg"
        fi
    done
    if (( has_file )); then
        cat >>"$DB_RT_SQL"
        printf '\n-- CALL END --\n' >>"$DB_RT_SQL"
    fi
    if printf '%s\n' "$@" | grep -Fq -- '--tuples-only'; then
        return 0
    fi
}

# Source shared helpers and provider modules without triggering main.
# shellcheck disable=SC1090
. "$ROOT/pm-helpers-db"
# shellcheck disable=SC1090
. "$ROOT/pm-provision-postgres"
# shellcheck disable=SC1090
. "$ROOT/pm-deploy-postgres"

pm_provision_db_provider
[[ "$DB_NAME" == generated_db ]] || fail ".env.generated DB_NAME was not loaded"
[[ "$DB_USER" == generated_user ]] || fail ".env.generated DB_USER was not loaded"
[[ "${PM_GENERATED_ENV_FILE_LOADED:-}" == "$(realpath "${ENV_FILE}.generated")" ]] \
    || fail "generated environment load marker was not set"

assert_contains "$DB_RT_SQL" "CREATE DATABASE %I OWNER %I"
assert_contains "$DB_RT_SQL" "ALTER DATABASE %I OWNER TO %I"
assert_contains "$DB_RT_SQL" "CREATE EXTENSION IF NOT EXISTS %I"
assert_contains "$DB_RT_SQL" "GRANT CONNECT, TEMPORARY"
assert_contains "$DB_RT_SQL" "\\gexec"

# Exercise migration lookup and recording. Both must use stdin/file mode.
pm_postgres_migration_table
pm_postgres_apply_migration "$SCRIPT_DIR/db/migrations/001_test.sql"
assert_contains "$DB_RT_SQL" "WHERE version = :'version';"
assert_contains "$DB_RT_SQL" "VALUES (:'version', :'checksum');"
assert_not_contains "$DB_RT_CALLS" "SCAFFOLD:"

printf 'PASS: Build 063 PostgreSQL psql file-mode and generated environment contract\n'

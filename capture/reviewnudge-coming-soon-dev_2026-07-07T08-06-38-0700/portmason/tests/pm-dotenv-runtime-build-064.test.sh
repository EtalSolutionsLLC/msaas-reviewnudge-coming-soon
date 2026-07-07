#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PORTMASON_SHARE="$(cd -- "$TEST_DIR/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log() { :; }
die() { echo "ERROR: $*" >&2; return "${2:-1}"; }
export -f log die

SCRIPT_DIR="$TMP"
PROJECT_ROOT="$TMP"
ENV_FILE="$TMP/.env"
DEPLOY_ENV=dev
export SCRIPT_DIR PROJECT_ROOT ENV_FILE DEPLOY_ENV PORTMASON_SHARE

cat > "${ENV_FILE}.generated" <<'ENV'
APP_SLUG=reviewnudge
DB_PASSWORD='local-password'
DATABASE_URL=postgresql://reviewnudge_app:local-password@db:5432/reviewnudge\?sslmode=disable
ENV

# shellcheck disable=SC1090
. "$PORTMASON_SHARE/pm-helpers-db"

DB_PROVIDER_PLATFORM_CODE=postgres-local
DB_PROVIDER=postgres
DB_PLATFORM=local
DB_HOST=db
DB_PORT=5432
DB_NAME=reviewnudge
DB_USER=reviewnudge_app
DB_PASSWORD=local-password
DATABASE_URL='postgresql://reviewnudge_app:local-password@db:5432/reviewnudge?sslmode=disable'
DATABASE_DIRECT_URL="$DATABASE_URL"
export DB_PROVIDER_PLATFORM_CODE DB_PROVIDER DB_PLATFORM DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD DATABASE_URL DATABASE_DIRECT_URL

pm_db_publish_generated_contract

if grep -Fq '\?' "${ENV_FILE}.generated"; then
    echo 'FAIL: generated dotenv contains Bash %q backslash before query delimiter' >&2
    exit 1
fi

expected="DATABASE_URL='postgresql://reviewnudge_app:local-password@db:5432/reviewnudge?sslmode=disable'"
grep -Fxq "$expected" "${ENV_FILE}.generated" || {
    echo 'FAIL: DATABASE_URL was not written as a Compose-compatible dotenv literal' >&2
    cat "${ENV_FILE}.generated" >&2
    exit 1
}

unset DATABASE_URL DATABASE_DIRECT_URL DB_NAME DB_HOST DB_PORT DB_USER
# shellcheck disable=SC1090
. "${ENV_FILE}.generated"
[[ "$DATABASE_URL" == 'postgresql://reviewnudge_app:local-password@db:5432/reviewnudge?sslmode=disable' ]] || {
    echo "FAIL: Bash load changed DATABASE_URL: $DATABASE_URL" >&2
    exit 1
}
[[ "$DB_NAME" == reviewnudge ]] || {
    echo "FAIL: Bash load changed DB_NAME: $DB_NAME" >&2
    exit 1
}

compose_rhs="${expected#*=}"
compose_value="${compose_rhs#\'}"
compose_value="${compose_value%\'}"
[[ "$compose_value" == 'postgresql://reviewnudge_app:local-password@db:5432/reviewnudge?sslmode=disable' ]] || {
    echo "FAIL: Compose-style literal decode changed DATABASE_URL: $compose_value" >&2
    exit 1
}
[[ "$compose_value" != *'reviewnudge\?'* ]] || {
    echo 'FAIL: Compose-style value retains the defective backslash' >&2
    exit 1
}

grep -Fxq "DB_PASSWORD='local-password'" "${ENV_FILE}.generated" || {
    echo 'FAIL: bridge publication rewrote DB_PASSWORD' >&2
    exit 1
}

echo 'PASS: Build 064 dotenv runtime contract'

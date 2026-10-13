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
DB_URL=postgresql://reviewnudge_app:local-password@db:5432/reviewnudge\?sslmode=disable
ENV

# shellcheck disable=SC1090
. "$PORTMASON_SHARE/pm-helpers-db"

DB_PROVIDER_PLATFORM_CODE=postgres-local
DB_PROVIDER_CODE=postgres
DB_PLATFORM_CODE=local
DB_HOST=db
DB_PORT=5432
DB_NAME=reviewnudge
DB_USER=reviewnudge_app
DB_PASSWORD=local-password
DB_URL='postgresql://reviewnudge_app:local-password@db:5432/reviewnudge?sslmode=disable'
DB_DIRECT_URL="$DB_URL"
export DB_PROVIDER_PLATFORM_CODE DB_PROVIDER_CODE DB_PLATFORM_CODE DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD DB_URL DB_DIRECT_URL

pm_db_publish_generated_contract

! grep -Eq '^(DB_PROVIDER|DB_PLATFORM)(_CODE)?=' "${ENV_FILE}.generated" || {
    echo 'FAIL: generated dotenv persisted derived database selectors' >&2
    exit 1
}

if grep -Fq '\?' "${ENV_FILE}.generated"; then
    echo 'FAIL: generated dotenv contains Bash %q backslash before query delimiter' >&2
    exit 1
fi

expected="DB_URL='postgresql://reviewnudge_app:local-password@db:5432/reviewnudge?sslmode=disable'"
grep -Fxq "$expected" "${ENV_FILE}.generated" || {
    echo 'FAIL: DB_URL was not written as a Compose-compatible dotenv literal' >&2
    cat "${ENV_FILE}.generated" >&2
    exit 1
}

unset DB_URL DB_DIRECT_URL DB_NAME DB_HOST DB_PORT DB_USER
# shellcheck disable=SC1090
. "${ENV_FILE}.generated"
[[ "$DB_URL" == 'postgresql://reviewnudge_app:local-password@db:5432/reviewnudge?sslmode=disable' ]] || {
    echo "FAIL: Bash load changed DB_URL: $DB_URL" >&2
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
    echo "FAIL: Compose-style literal decode changed DB_URL: $compose_value" >&2
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

cat > "$TMP/commented.env" <<'ENV'
APP_SLUG=comment-test
OWNER_ALIAS=etalsolutions             # Allowed: etalsolutions | client-it | other
MANAGED_BY=compose              # Allowed: compose | k8s | terraform | manual | other
LITERAL_HASH="keep # inside quotes"
ENV

"$PORTMASON_SHARE/pm-util-render-env" --dotenv --out "$TMP/commented.env.generated" "$TMP/commented.env"
grep -Fxq 'OWNER_ALIAS=etalsolutions' "$TMP/commented.env.generated" || {
    echo 'FAIL: dotenv renderer preserved inline operator comment in OWNER_ALIAS' >&2
    cat "$TMP/commented.env.generated" >&2
    exit 1
}
grep -Fxq 'MANAGED_BY=compose' "$TMP/commented.env.generated" || {
    echo 'FAIL: dotenv renderer preserved inline operator comment in MANAGED_BY' >&2
    cat "$TMP/commented.env.generated" >&2
    exit 1
}
grep -Fxq 'LITERAL_HASH="keep # inside quotes"' "$TMP/commented.env.generated" || {
    echo 'FAIL: dotenv renderer stripped quoted hash literal' >&2
    cat "$TMP/commented.env.generated" >&2
    exit 1
}

echo 'PASS: Build 064 dotenv runtime contract'

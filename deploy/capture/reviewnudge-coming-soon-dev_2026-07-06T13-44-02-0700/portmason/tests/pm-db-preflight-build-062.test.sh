#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM
mkdir -p "$temp_dir/project"
TEST_LOG="$temp_dir/preflight.log"

log() { printf '%s\n' "$*" >>"$TEST_LOG"; }
die() { log ERROR "$*"; return "${2:-1}"; }
have() { command -v "$1" >/dev/null 2>&1; }
env_init_set() { printf -v "$1" '%s' "${2-}"; export "$1"; }
export -f log die have env_init_set

export PORTMASON_SHARE="$source_dir"
export SCRIPT_DIR="$temp_dir/project"
export ENV_FILE="$temp_dir/project/.env"
export APP_SLUG=
export DEPLOY_ENV=prd
export RUNTIME_ADAPTER_CODE=badselector
export RUNTIME_CODE=
export ADAPTER_CODE=
export STACK=
export DB_PROVIDER_PLATFORM_CODE=absent-missing
export DB_PROVIDER=absent
export DB_PLATFORM=missing
export DB_NAME=
export DB_USER=
export DB_PASSWORD=change-this-in-production
export DB_PORT=70000
export PM_ADDITIONAL_SECRET_KEYS=
export PM_REQUIRED_SECRET_KEYS=
export SECRET_PATHS=

cat >"${ENV_FILE}.generated" <<'ENV'
UNREGISTERED_API_KEY=something-private
DB_PASSWORD=change-this-in-production
ENV

. "$source_dir/pm-helpers-db"

# Keep this test focused on aggregate validation rather than Docker tooling.
pm_compose_load_model() {
    PROJECT_SERVICES='[
      {"service":"db","role":"db","image":"postgres","has_build":false,"command":[],"entrypoint":[],"depends_on":[]},
      {"service":"database","role":"db","image":"postgres","has_build":false,"command":[],"entrypoint":[],"depends_on":[]},
      {"service":"web","role":"web","image":"app","has_build":true,"command":[],"entrypoint":[],"depends_on":["db"]}
    ]'
    export PROJECT_SERVICES
    return 0
}

if pm_db_preflight; then
    printf 'Expected aggregate preflight to fail.\n' >&2
    exit 1
fi

(( ${#PM_PREFLIGHT_ERRORS[@]} >= 12 ))
joined="$(printf '%s\n' "${PM_PREFLIGHT_ERRORS[@]}")"
for expected in \
    'project|APP_SLUG|' \
    'runtime.selector|RUNTIME_ADAPTER_CODE|' \
    'project|STACK|' \
    'database.contract|DB_NAME|' \
    'database.contract|DB_USER|' \
    'database.contract|DB_PORT|' \
    'secret.registry|UNREGISTERED_API_KEY|' \
    'secret.quality|DB_PASSWORD|' \
    'compose.roles|db|' \
    'database.module|pm-helpers-absent|' \
    'database.module|pm-helpers-missing|' \
    'database.module|pm-db-bridge-absent-missing|' \
    'database.module|pm-provision-missing|' \
    'database.module|pm-deploy-missing|' \
    'database.module|pm-provision-absent|' \
    'database.module|pm-deploy-absent|'
do
    grep -Fq "$expected" <<<"$joined"
done

! grep -Fq 'safety.arm|' <<<"$joined"

grep -Fq 'no provisioning or deployment actions were started' "$TEST_LOG"
printf 'Portmason aggregate preflight tests passed (%s findings).\n' "${#PM_PREFLIGHT_ERRORS[@]}"

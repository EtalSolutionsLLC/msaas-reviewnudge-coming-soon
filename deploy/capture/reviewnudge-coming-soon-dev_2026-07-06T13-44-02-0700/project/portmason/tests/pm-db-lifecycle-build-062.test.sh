#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM
mkdir -p "$temp_dir/project/db/migrations" "$temp_dir/project/db/seeds" "$temp_dir/gcp" "$temp_dir/bin"

TEST_LOG="$temp_dir/test.log"
TRACE="$temp_dir/trace.log"
log() { printf '%s\n' "$*" >>"$TEST_LOG"; }
die() { log ERROR "$*"; return "${2:-1}"; }
have() { command -v "$1" >/dev/null 2>&1; }
env_init_set() { printf -v "$1" '%s' "${2-}"; export "$1"; }
pm_db_call_optional() { local fn="$1"; shift; declare -F "$fn" >/dev/null 2>&1 && "$fn" "$@" || true; }
export -f log die have env_init_set pm_db_call_optional

export PORTMASON_SHARE="$source_dir"
export SCRIPT_DIR="$temp_dir/project"
export ENV_FILE="$temp_dir/project/.env"
export DEPLOY_ENV=dev
export DB_PROVIDER=postgres DB_PLATFORM=local DB_PROVIDER_PLATFORM_CODE=postgres-local
export DB_HOST=db DB_PORT=5432 DB_NAME=appdb DB_USER=appuser DB_PASSWORD='local-test-password'
export DB_ADMIN_USER=postgres DB_ADMIN_PASSWORD='admin-test-password'

. "$source_dir/pm-helpers-postgres"

# Provider lifecycle uses the bridge contract without owning transport details.
db_rt() {
    printf '%q ' "$@" >>"$TRACE"
    printf '\n' >>"$TRACE"
    if [[ "$*" == *"SELECT checksum_sha256"* ]]; then
        return 0
    fi
    if [[ "$*" == *"current_database()"* ]]; then
        printf 'appdb|appuser\n'
    fi
    if [[ "$*" == *"--file=-"* ]]; then
        cat >>"$TRACE"
        printf '\n' >>"$TRACE"
    fi
}
export -f db_rt

cat > "$temp_dir/project/db/migrations/001-create.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS build_062_test(id integer PRIMARY KEY);
SQL

. "$source_dir/pm-provision-postgres"
. "$source_dir/pm-deploy-postgres"
pm_provision_db_provider
pm_deploy_db_provider

grep -Fq 'CREATE ROLE' "$TRACE"
grep -Fq 'CREATE DATABASE' "$TRACE"
grep -Fq '001-create.sql' "$TEST_LOG"
grep -Fq 'provider verification passed' "$TEST_LOG"

# Mock GCP Secret Manager and verify sync/dedup without logging values.
cat > "$temp_dir/bin/gcloud" <<'GCLOUD'
#!/usr/bin/env bash
set -euo pipefail
root="${MOCK_GCP_ROOT:?}"
printf '%q ' "$@" >>"${MOCK_GCP_TRACE:?}"
printf '\n' >>"${MOCK_GCP_TRACE:?}"

if [[ "$1 $2" == "secrets describe" ]]; then
    secret="$3"; project=""
    while (($#)); do [[ "$1" == "--project" ]] && project="$2"; shift || true; done
    [[ -f "$root/$project/$secret.meta" ]]
    exit
fi
if [[ "$1 $2" == "secrets create" ]]; then
    secret="$3"; project=""
    while (($#)); do [[ "$1" == "--project" ]] && project="$2"; shift || true; done
    mkdir -p "$root/$project"; : >"$root/$project/$secret.meta"; exit 0
fi
if [[ "$1 $2 $3" == "secrets versions access" ]]; then
    project=""; secret=""; outfile=""
    while (($#)); do
        case "$1" in --project) project="$2"; shift;; --secret) secret="$2"; shift;; --out-file) outfile="$2"; shift;; esac
        shift || true
    done
    [[ -f "$root/$project/$secret.value" ]] || exit 1
    if [[ -n "$outfile" ]]; then cp "$root/$project/$secret.value" "$outfile"; else cat "$root/$project/$secret.value"; fi
    exit 0
fi
if [[ "$1 $2 $3" == "secrets versions add" ]]; then
    secret="$4"; project=""
    while (($#)); do [[ "$1" == "--project" ]] && project="$2"; shift || true; done
    mkdir -p "$root/$project"; cat >"$root/$project/$secret.value"; exit 0
fi
if [[ "$1 $2" == "secrets add-iam-policy-binding" ]]; then exit 0; fi
exit 0
GCLOUD
chmod +x "$temp_dir/bin/gcloud"
export PATH="$temp_dir/bin:$PATH"
export MOCK_GCP_ROOT="$temp_dir/gcp"
export MOCK_GCP_TRACE="$temp_dir/gcp-trace.log"
export STACK=reviewnudge-prd DEPLOYMENT_ID=reviewnudge-prd-123 DEPLOY_ENV=prd
export PROJECT_SERVICES='[{"service":"web","role":"web","image":"image","has_build":true,"command":[],"entrypoint":[],"depends_on":["db"]}]'
export DB_PASSWORD='super-secret-value-062'
export DB_USER='reviewnudge_app'
export DATABASE_URL='postgresql://reviewnudge_app:super-secret-value-062@localhost/reviewnudge'
export PM_ADDITIONAL_SECRET_KEYS=
export SECRET_PATHS=
export ENV_FILE="$temp_dir/project/.env"
cat > "${ENV_FILE}.generated" <<ENV
DB_PASSWORD=$DB_PASSWORD
DB_USER=$DB_USER
DATABASE_URL=$DATABASE_URL
ENV

# Minimal functions required by the GCP helper come from pm-helpers-db.
env_file_to_kv_nul() {
    local file="$1" key value
    while IFS='=' read -r key value; do
        [[ -n "$key" ]] && printf '%s\0%s\0' "$key" "$value"
    done <"$file"
}
export -f env_file_to_kv_nul
. "$source_dir/pm-helpers-db"
. "$source_dir/pm-helpers-gcp-secrets"
pm_gcp_sync_project_runtime_secrets
first_count="$(grep -c 'secrets versions add' "$MOCK_GCP_TRACE")"
pm_gcp_sync_project_runtime_secrets
second_count="$(grep -c 'secrets versions add' "$MOCK_GCP_TRACE")"
[[ "$first_count" -ge 3 ]]
[[ "$first_count" == "$second_count" ]]
[[ -f "$MOCK_GCP_ROOT/$DEPLOYMENT_ID/reviewnudge-prd-db-password.value" ]]
! grep -Fq 'super-secret-value-062' "$TEST_LOG"

printf 'Portmason PostgreSQL and GCP-secret lifecycle tests passed.\n'

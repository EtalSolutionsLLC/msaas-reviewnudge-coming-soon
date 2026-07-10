#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM
mkdir -p "$temp_dir/bin" "$temp_dir/project/db/migrations"
TRACE="$temp_dir/trace.log"
TEST_LOG="$temp_dir/test.log"

log() { printf '%s\n' "$*" >>"$TEST_LOG"; }
die() { log ERROR "$*"; return "${2:-1}"; }
have() { command -v "$1" >/dev/null 2>&1; }
env_init_set() { printf -v "$1" '%s' "${2-}"; export "$1"; }
pm_preflight_error() { printf 'ERR|%s|%s|%s\n' "$1" "$2" "$3" >>"$TEST_LOG"; }
pm_preflight_require_secret() { local _c="$1" key="$2" msg="$3"; [[ -n "${!key:-}" ]] || pm_preflight_error "$_c" "$key" "$msg"; }
pm_db_call_optional() { local fn="$1"; shift; declare -F "$fn" >/dev/null 2>&1 && "$fn" "$@" || true; }
export -f log die have env_init_set pm_preflight_error pm_preflight_require_secret pm_db_call_optional

cat > "$temp_dir/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
method=GET output='' url=''
while (($#)); do
  case "$1" in
    --request) method="$2"; shift ;;
    --output) output="$2"; shift ;;
    --write-out) shift ;;
    --data|--header|--connect-timeout|--max-time) shift ;;
    http*) url="$1" ;;
  esac
  shift || true
done
path="${url#*api/v2}"
printf '%s %s\n' "$method" "$path" >>"${MOCK_TRACE:?}"
case "$method $path" in
  'GET /projects?limit=100&org_id=org-062') body='{"projects":[]}' ;;
  'POST /projects?org_id=org-062') body='{"project":{"id":"prj_062","name":"reviewnudge-prd"},"branch":{"id":"br_062","name":"main"},"endpoints":[{"id":"ep_062","branch_id":"br_062","type":"read_write"}],"operations":[]}' ;;
  'GET /projects/prj_062/branches') body='{"branches":[{"id":"br_062","name":"main","default":true}]}' ;;
  'GET /projects/prj_062/endpoints') body='{"endpoints":[{"id":"ep_062","branch_id":"br_062","type":"read_write","disabled":false,"current_state":"active"}]}' ;;
  'GET /projects/prj_062/branches/br_062/roles') body='{"roles":[{"name":"neondb_owner","protected":true}]}' ;;
  'GET /projects/prj_062/branches/br_062/databases') body='{"databases":[{"name":"neondb","owner_name":"neondb_owner"}]}' ;;
  GET\ /projects/prj_062/connection_uri*)
    if [[ "$path" == *'pooled=true'* ]]; then
      body='{"uri":"postgresql://neondb_owner:admin-secret@ep-062-pooler.us-west-2.aws.neon.tech:5432/neondb?sslmode=require"}'
    else
      body='{"uri":"postgresql://neondb_owner:admin-secret@ep-062.us-west-2.aws.neon.tech:5432/neondb?sslmode=require"}'
    fi
    ;;
  *) body='{}' ;;
esac
printf '%s' "$body" >"$output"
printf '200'
CURL
chmod +x "$temp_dir/bin/curl"

cat > "$temp_dir/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"${MOCK_TRACE:?}"
printf '\n' >>"${MOCK_TRACE:?}"
args="$*"
if [[ " $args " == *" --file=- "* ]]; then
  cat >>"${MOCK_TRACE:?}"
fi
if [[ "$args" == *'SELECT current_database() ||'* ]]; then
  printf '%s|%s\n' "${PGDATABASE:-appdb}" "${PGUSER:-appuser}"
elif [[ "$args" == *'SELECT checksum_sha256'* ]]; then
  :
fi
DOCKER
chmod +x "$temp_dir/bin/docker"

export PATH="$temp_dir/bin:$PATH"
export MOCK_TRACE="$TRACE"
export PORTMASON_SHARE="$source_dir" SCRIPT_DIR="$temp_dir/project"
export DEPLOY_ENV=prd STACK=reviewnudge-prd ADAPTER_CODE=local
export DB_PROVIDER_PLATFORM_CODE=postgres-neon DB_PROVIDER_CODE=postgres DB_PLATFORM_CODE=neon
export DB_NAME=appdb DB_USER=appuser DB_PASSWORD=app-secret
export DB_API_KEY=neon-api-key NEON_PROJECT_NAME=reviewnudge-prd NEON_ORG_ID=org-062
export NEON_BRANCH_NAME=main NEON_REGION_ID=aws-us-west-2 NEON_PG_VERSION=17
export NEON_USE_POOLER=true

cat > "$temp_dir/project/db/migrations/001-create.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS build_062_neon(id integer PRIMARY KEY);
SQL

. "$source_dir/pm-helpers-postgres"
. "$source_dir/pm-helpers-neon"
. "$source_dir/pm-provision-neon"
. "$source_dir/pm-db-bridge-postgres-neon"
. "$source_dir/pm-provision-postgres"
. "$source_dir/pm-deploy-neon"
. "$source_dir/pm-deploy-postgres"

pm_provision_db_platform
pm_db_bridge_provision
pm_provision_db_provider
pm_deploy_db_platform
pm_db_bridge_deploy
pm_deploy_db_provider

[[ "$NEON_PROJECT_ID" == prj_062 ]]
[[ "$NEON_BRANCH_ID" == br_062 ]]
[[ "$NEON_ENDPOINT_ID" == ep_062 ]]
[[ "$DB_HOST" == ep-062-pooler.us-west-2.aws.neon.tech ]]
[[ "$NEON_DIRECT_HOST" == ep-062.us-west-2.aws.neon.tech ]]
[[ "$DATABASE_URL" == postgresql://appuser:app-secret@ep-062-pooler.us-west-2.aws.neon.tech:5432/appdb?sslmode=require ]]
[[ "$DATABASE_DIRECT_URL" == postgresql://appuser:app-secret@ep-062.us-west-2.aws.neon.tech:5432/appdb?sslmode=require ]]
grep -Fq 'GET /projects?limit=100&org_id=org-062' "$TRACE"
grep -Fq 'POST /projects?org_id=org-062' "$TRACE"
grep -Fq 'CREATE ROLE' "$TRACE"
grep -Fq '001-create.sql' "$TEST_LOG"
grep -Fq 'endpoint verified' "$TEST_LOG"
grep -Fq 'deploy binding verified' "$TEST_LOG"
! grep -Fq 'admin-secret' "$TEST_LOG"
! grep -Fq 'neon-api-key' "$TEST_LOG"

# Control-plane credentials are canonical but never part of a runtime role.
. "$source_dir/pm-helpers-db"
! pm_service_secret_keys web | grep -Fxq DB_API_KEY

printf 'Portmason PostgreSQL-Neon lifecycle tests passed.\n'

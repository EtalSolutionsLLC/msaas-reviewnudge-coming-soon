#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM
mkdir -p "$temp_dir/bin" "$temp_dir/project/db/migrations" "$temp_dir/gcp"
TEST_LOG="$temp_dir/test.log"
GCLOUD_TRACE="$temp_dir/gcloud.trace"
DOCKER_TRACE="$temp_dir/docker.trace"
NEON_TRACE="$temp_dir/neon.trace"

log() { printf '%s\n' "$*" >>"$TEST_LOG"; }
die() { log ERROR "$*"; return "${2:-1}"; }
have() { command -v "$1" >/dev/null 2>&1; }
env_init_set() { printf -v "$1" '%s' "${2-}"; export "$1"; }
log_cmd() { printf 'CMD '; printf '%q ' "$@" >>"$TEST_LOG"; printf '\n' >>"$TEST_LOG"; }
format_sa_email() { printf '%s@%s.iam.gserviceaccount.com' "$1" "$DEPLOYMENT_ID"; }
pm_setup_arg() { :; }
pm_commit_args() { :; }
export -f log die have env_init_set log_cmd format_sa_email pm_setup_arg pm_commit_args

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
printf '%s %s\n' "$method" "$path" >>"${MOCK_NEON_TRACE:?}"
case "$method $path" in
  'GET /projects?limit=100&org_id=org-062') body='{"projects":[]}' ;;
  'POST /projects?org_id=org-062') body='{"project":{"id":"prj-062","name":"reviewnudge-prd"},"branch":{"id":"br-062","name":"main"},"endpoints":[{"id":"ep-062","branch_id":"br-062","type":"read_write"}],"operations":[]}' ;;
  'GET /projects/prj-062/branches') body='{"branches":[{"id":"br-062","name":"main","default":true}]}' ;;
  'GET /projects/prj-062/endpoints') body='{"endpoints":[{"id":"ep-062","branch_id":"br-062","type":"read_write","disabled":false,"current_state":"active"}]}' ;;
  'GET /projects/prj-062/branches/br-062/roles') body='{"roles":[{"name":"neondb_owner","protected":true}]}' ;;
  'GET /projects/prj-062/branches/br-062/databases') body='{"databases":[{"name":"neondb","owner_name":"neondb_owner"}]}' ;;
  GET\ /projects/prj-062/connection_uri*)
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
printf '%q ' "$@" >>"${MOCK_DOCKER_TRACE:?}"
printf '\n' >>"${MOCK_DOCKER_TRACE:?}"
args="$*"
if [[ "$args" == *'--file=-'* ]]; then cat >/dev/null; fi
if [[ "$args" == *'current_database()'* ]]; then printf '%s|%s\n' "${PGDATABASE:-reviewnudge}" "${PGUSER:-reviewnudge_app}"; fi
exit 0
DOCKER
chmod +x "$temp_dir/bin/docker"

cat > "$temp_dir/bin/gcloud" <<'GCLOUD'
#!/usr/bin/env bash
set -euo pipefail
root="${MOCK_GCP_ROOT:?}"
printf '%q ' "$@" >>"${MOCK_GCLOUD_TRACE:?}"
printf '\n' >>"${MOCK_GCLOUD_TRACE:?}"
for ((i=1; i<=$#; i++)); do
  if [[ "${!i}" == "--env-vars-file" ]]; then
    j=$((i+1)); printf '%s\n' '---ENV-FILE---' >>"${MOCK_GCLOUD_TRACE:?}"; cat "${!j}" >>"${MOCK_GCLOUD_TRACE:?}"
  fi
done
if [[ "$1 $2" == "secrets describe" ]]; then
  secret="$3"; project=''
  while (($#)); do [[ "$1" == "--project" ]] && project="$2"; shift || true; done
  [[ -f "$root/$project/$secret.meta" ]]; exit
fi
if [[ "$1 $2" == "secrets create" ]]; then
  secret="$3"; project=''
  while (($#)); do [[ "$1" == "--project" ]] && project="$2"; shift || true; done
  mkdir -p "$root/$project"; : >"$root/$project/$secret.meta"; exit 0
fi
if [[ "$1 $2 $3" == "secrets versions access" ]]; then
  project=''; secret=''; outfile=''
  while (($#)); do
    case "$1" in --project) project="$2"; shift;; --secret) secret="$2"; shift;; --out-file) outfile="$2"; shift;; esac
    shift || true
  done
  [[ -f "$root/$project/$secret.value" ]] || exit 1
  if [[ -n "$outfile" ]]; then cp "$root/$project/$secret.value" "$outfile"; else cat "$root/$project/$secret.value"; fi
  exit 0
fi
if [[ "$1 $2 $3" == "secrets versions add" ]]; then
  secret="$4"; project=''
  while (($#)); do [[ "$1" == "--project" ]] && project="$2"; shift || true; done
  mkdir -p "$root/$project"; cat >"$root/$project/$secret.value"; exit 0
fi
if [[ "$1 $2" == "secrets add-iam-policy-binding" ]]; then exit 0; fi
if [[ "$1 $2" == "projects add-iam-policy-binding" ]]; then exit 0; fi
if [[ "$1 $2" == "config set" ]]; then exit 0; fi
if [[ "$1 $2" == "auth configure-docker" ]]; then exit 0; fi
if [[ "$1 $2" == "run deploy" ]]; then exit 0; fi
if [[ "$1 $2 $3" == "run services describe" ]]; then printf 'https://reviewnudge.run.app\n'; exit 0; fi
if [[ "$1 $2 $3" == "run jobs describe" ]]; then exit 1; fi
if [[ "$1 $2 $3" == "run jobs create" ]]; then exit 0; fi
exit 0
GCLOUD
chmod +x "$temp_dir/bin/gcloud"

export PATH="$temp_dir/bin:$PATH"
export MOCK_GCP_ROOT="$temp_dir/gcp" MOCK_GCLOUD_TRACE="$GCLOUD_TRACE"
export MOCK_DOCKER_TRACE="$DOCKER_TRACE" MOCK_NEON_TRACE="$NEON_TRACE"
export PORTMASON_SHARE="$source_dir" SCRIPT_DIR="$temp_dir/project"
export ENV_FILE="$temp_dir/project/.env" DEPLOY_ENV=prd
export APP_SLUG=reviewnudge STACK=reviewnudge-prd
export RUNTIME_ADAPTER_CODE=node-gcp RUNTIME_CODE=node ADAPTER_CODE=gcp
export DB_PROVIDER_PLATFORM_CODE=postgres-neon DB_PROVIDER=postgres DB_PLATFORM=neon
export DEPLOYMENT_ID=reviewnudge-prd-062 REGION=us-central1 AR_REPO=reviewnudge
export DB_NAME=reviewnudge DB_USER=reviewnudge_app DB_PASSWORD='application-secret-062'
export NEON_API_KEY='neon-control-secret-062' NEON_ORG_ID=org-062
export NEON_PROJECT_NAME=reviewnudge-prd NEON_BRANCH_NAME=main NEON_REGION_ID=aws-us-west-2 NEON_PG_VERSION=17 NEON_USE_POOLER=true
export PORT=3080 PM_HEALTH_PATH=/livez PM_ADDITIONAL_SECRET_KEYS= PM_REQUIRED_SECRET_KEYS=
export SECRET_PATHS= BLOCKED_SHORTENER_DOMAINS='bit.ly,tinyurl.com,t.co'
cat > "${ENV_FILE}.generated" <<ENV
APP_SLUG=reviewnudge
DEPLOY_ENV=prd
RUNTIME_ADAPTER_CODE=node-gcp
DB_PROVIDER_PLATFORM_CODE=postgres-neon
DB_NAME=reviewnudge
DB_USER=reviewnudge_app
DB_PASSWORD=application-secret-062
PORT=3080
BLOCKED_SHORTENER_DOMAINS=bit.ly,tinyurl.com,t.co
ENV
cat > "$temp_dir/project/db/migrations/001-public.sql" <<'SQL'
CREATE TABLE IF NOT EXISTS build_062_production(id integer PRIMARY KEY);
SQL

# Minimal dotenv reader used by the shared runtime-environment contract.
env_file_to_kv_nul() {
  local file="$1" key value
  while IFS='=' read -r key value; do
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] && printf '%s\0%s\0' "$key" "$value"
  done <"$file"
}
export -f env_file_to_kv_nul

. "$source_dir/pm-helpers-db"
. "$source_dir/pm-helpers-postgres"
. "$source_dir/pm-helpers-gcp-secrets"
. "$source_dir/pm-helpers-neon"
. "$source_dir/pm-provision-neon"
. "$source_dir/pm-db-bridge-postgres-neon"
. "$source_dir/pm-provision-postgres"
. "$source_dir/pm-deploy-neon"
. "$source_dir/pm-deploy-postgres"

# The helper module initializes shared model variables. Populate the mocked
# Compose contract only after it has been sourced.
PROJECT_SERVICES='[{"service":"web","role":"web","image":"reviewnudge:062","has_build":false,"command":[],"entrypoint":[],"depends_on":[]}]'
PM_COMPOSE_MODEL_JSON='{"services":{"web":{"image":"reviewnudge:062","labels":{"solutions.etal.service":"web"}}}}'
PM_COMPOSE_CMD=(docker compose -f "$temp_dir/project/docker-compose.yml")
export PM_COMPOSE_MODEL_JSON PROJECT_SERVICES

pm_provision_db_platform
pm_db_bridge_provision
pm_provision_db_provider
pm_deploy_db_platform
pm_db_bridge_deploy
pm_deploy_db_provider

# Load the independently replaceable GCP runtime module only after the Neon
# database phases have completed, matching pm-setup lifecycle resolution.
. "$source_dir/pm-deploy-gcp"
pm_deploy_runtime_platform

# The app runtime is GCP; the database platform remains Neon.
grep -Fq 'POST /projects?org_id=org-062' "$NEON_TRACE"
grep -Fq -- 'run deploy reviewnudge-prd-web' "$GCLOUD_TRACE"
grep -Fq -- '--env-vars-file' "$GCLOUD_TRACE"
grep -Fq -- '--port 3080' "$GCLOUD_TRACE"
grep -Fq 'BLOCKED_SHORTENER_DOMAINS: "bit.ly,tinyurl.com,t.co"' "$GCLOUD_TRACE"
grep -Fq -- '--set-secrets DB_PASSWORD=projects/reviewnudge-prd-062/secrets/reviewnudge-prd-db-password:latest' "$GCLOUD_TRACE"
! grep -Fq -- '--add-cloudsql-instances' "$GCLOUD_TRACE"
! grep -Fq -- 'NEON_API_KEY=' "$GCLOUD_TRACE"
! grep -Fq 'application-secret-062' "$TEST_LOG" "$GCLOUD_TRACE" "$DOCKER_TRACE"
! grep -Fq 'neon-control-secret-062' "$TEST_LOG" "$GCLOUD_TRACE" "$DOCKER_TRACE"
grep -Fq 'runtime platform deployment complete' "$TEST_LOG"

printf 'Portmason ReviewNudge GCP runtime with Neon PostgreSQL contract test passed.\n'

#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM
mkdir -p "$temp_dir/bin" "$temp_dir/state"
TRACE="$temp_dir/gcloud.trace"
TEST_LOG="$temp_dir/test.log"

log() { printf '%s\n' "$*" >>"$TEST_LOG"; }
die() { log ERROR "$*"; return "${2:-1}"; }
have() { command -v "$1" >/dev/null 2>&1; }
env_init_set() { printf -v "$1" '%s' "${2-}"; export "$1"; }
log_cmd() { printf 'CMD '; printf '%q ' "$@" >>"$TEST_LOG"; printf '\n' >>"$TEST_LOG"; }
format_sa_email() { printf '%s@%s.iam.gserviceaccount.com' "$1" "$DEPLOYMENT_ID"; }
pm_gcp_write_env_file_for_role() { local out="$1" file; file="$(mktemp)"; printf '%s\n' 'DB_HOST: "/cloudsql/project:region:instance"' 'BLOCKED_SHORTENER_DOMAINS: "bit.ly,tinyurl.com"' >"$file"; printf -v "$out" '%s' "$file"; }
pm_gcp_secret_args_for_role() { printf '%s\0%s\0' --set-secrets 'DB_PASSWORD=projects/project/secrets/stack-db-password:latest'; }
pm_gcp_sync_project_runtime_secrets() { printf 'sync-runtime-secrets\n' >>"${MOCK_TRACE:?}"; }
pm_gcp_bind_service_secret_access() { printf 'bind-secret-access %s %s\n' "$1" "$2" >>"${MOCK_TRACE:?}"; }
export -f log die have env_init_set log_cmd format_sa_email pm_gcp_write_env_file_for_role pm_gcp_secret_args_for_role pm_gcp_sync_project_runtime_secrets pm_gcp_bind_service_secret_access

cat > "$temp_dir/bin/gcloud" <<'GCLOUD'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"${MOCK_TRACE:?}"
printf '\n' >>"${MOCK_TRACE:?}"
for ((i=1; i<=$#; i++)); do
  if [[ "${!i}" == "--env-vars-file" ]]; then j=$((i+1)); printf '%s\n' '---ENV-FILE---' >>"${MOCK_TRACE:?}"; cat "${!j}" >>"${MOCK_TRACE:?}"; fi
done
state="${MOCK_STATE:?}"
if [[ "$1 $2 $3" == "sql instances describe" ]]; then
    instance="$4"
    if [[ "$*" == *"format=value(connectionName)"* ]]; then
        printf 'project:us-central1:%s\n' "$instance"
        exit 0
    fi
    [[ -f "$state/$instance" ]]
    exit
fi
if [[ "$1 $2 $3" == "sql instances create" ]]; then
    touch "$state/$4"
    exit 0
fi
if [[ "$1 $2" == "run deploy" ]]; then exit 0; fi
if [[ "$1 $2 $3" == "run services describe" ]]; then printf 'https://service.run.app\n'; exit 0; fi
exit 0
GCLOUD
chmod +x "$temp_dir/bin/gcloud"
export PATH="$temp_dir/bin:$PATH"
export MOCK_TRACE="$TRACE" MOCK_STATE="$temp_dir/state"
export PORTMASON_SHARE="$source_dir"
export DEPLOYMENT_ID=project REGION=us-central1 STACK=stack APP_SLUG=stack AR_REPO=stack
export ADAPTER_CODE=gcp DB_PLATFORM_CODE=gcp DB_PROVIDER_CODE=postgres CLOUD_SQL_CONNECTION_NAME=project:us-central1:stack-postgres PORT=3080

. "$source_dir/pm-provision-gcp"
pm_gcp_ensure_postgres_instance stack-postgres
pm_gcp_resolve_cloud_sql_connection stack-postgres
[[ "$CLOUD_SQL_CONNECTION_NAME" == 'project:us-central1:stack-postgres' ]]
grep -Fq -- '--database-version POSTGRES_16' "$TRACE"
grep -Fq -- '--tier db-f1-micro' "$TRACE"

. "$source_dir/pm-deploy-gcp"
pm_gcp_deploy_cloud_run_service web web image:062

grep -Fq -- '--add-cloudsql-instances project:us-central1:stack-postgres' "$TRACE"
grep -Fq -- '--set-secrets DB_PASSWORD=projects/project/secrets/stack-db-password:latest' "$TRACE"
grep -Fq -- '--env-vars-file' "$TRACE"
grep -Fq -- '--port 3080' "$TRACE"
grep -Fq 'BLOCKED_SHORTENER_DOMAINS: "bit.ly,tinyurl.com"' "$TRACE"
grep -Fq -- '--service-account web@project.iam.gserviceaccount.com' "$TRACE"
! grep -Fq 'plaintext-password' "$TRACE"
grep -Fq 'Cloud Run service deployment complete' "$TEST_LOG"
grep -Fq 'pm_gcp_sync_project_runtime_secrets' "$source_dir/pm-deploy-gcp"
grep -Fq 'pm_gcp_bind_service_secret_access' "$source_dir/pm-deploy-gcp"

printf 'Portmason GCP Cloud SQL and Cloud Run command-contract tests passed.\n'

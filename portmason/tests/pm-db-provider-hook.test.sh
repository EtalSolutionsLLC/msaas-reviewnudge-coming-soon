#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM
mkdir -p "$temp_dir/bin" "$temp_dir/project"

cat > "$temp_dir/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"config --format json"* ]]; then
cat <<'JSON'
{"services":{"db":{"image":"postgres:17-alpine","labels":{"solutions.etal.service":"db"}},"web":{"image":"test-web","labels":{"solutions.etal.service":"web"},"depends_on":{"db":{"condition":"service_healthy"}}}}}
JSON
exit 0
fi
exit 0
DOCKER
chmod +x "$temp_dir/bin/docker"
export PATH="$temp_dir/bin:$PATH"

TEST_LOG="$temp_dir/preflight.log"
log() { printf '%s\n' "$*" >>"$TEST_LOG"; }
die() { log ERROR "$*"; return "${2:-1}"; }
have() { command -v "$1" >/dev/null 2>&1; }
env_init_set() { printf -v "$1" '%s' "${2-}"; export "$1"; }
env_file_to_kv_nul() { :; }
export -f log die have env_init_set env_file_to_kv_nul

export PORTMASON_SHARE="$source_dir"
export SCRIPT_DIR="$temp_dir/project"
export ENV_FILE="$temp_dir/project/.env"
touch "$ENV_FILE"
cat > "${ENV_FILE}.generated" <<'ENV'
UNKNOWN_API_KEY=not-registered
MESSAGE_TRANSPORT=bulkemailer
BULKEMAILER_PROVIDER=resend
TURNSTILE_ENABLED=true
ENV

# First-hyphen selector behavior.
DB_PROVIDER_PLATFORM_CODE=mssql-azuremanaged
unset DB_PROVIDER_CODE DB_PLATFORM_CODE
. "$source_dir/pm-helpers-db"
pm_db_refresh_selectors
[[ "$DB_PROVIDER_CODE" == "mssql" ]]
[[ "$DB_PLATFORM_CODE" == "azuremanaged" ]]

# Aggregate preflight must report every defect, not stop after the first.
DB_PROVIDER_PLATFORM_CODE=postgres-local
RUNTIME_ADAPTER_CODE=node-local
ADAPTER_CODE=local
APP_SLUG=""
STACK=""
DEPLOY_ENV=prd
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
DB_PORT=not-a-port
MESSAGE_TRANSPORT=bulkemailer
BULKEMAILER_PROVIDER=resend
TURNSTILE_ENABLED=true
unset BULKEMAILER_API_KEY TURNSTILE_SECRET_KEY PM_DB_POSTGRES_PARSE_ERROR

rc=0
if pm_db_preflight; then
    rc=0
else
    rc=$?
fi
[[ "$rc" -eq 2 ]]

for required in APP_SLUG STACK DB_NAME DB_USER DB_PASSWORD DB_PORT BULKEMAILER_API_KEY TURNSTILE_SECRET_KEY UNKNOWN_API_KEY; do
    grep -Fq "$required" "$TEST_LOG" || {
        printf 'Expected aggregate preflight report to contain %s\n' "$required" >&2
        cat "$TEST_LOG" >&2
        exit 1
    }
done

grep -Fq 'no provisioning or deployment actions were started' "$TEST_LOG"
printf 'Portmason selector and aggregate-preflight tests passed.\n'

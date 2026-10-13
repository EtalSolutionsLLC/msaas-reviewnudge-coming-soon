#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM
mkdir -p "$temp_dir/bin" "$temp_dir/project"
printf '%s\n' 'DB_API_KEY=plaintext-value-from-dotenv' >"$temp_dir/project/.env"

cat >"$temp_dir/bin/gcloud" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1 $2 $3" == "projects describe test-gcp-project" ]]; then
    printf '{"projectNumber":"123456789"}\n'
    exit 0
fi
if [[ "$1 $2 $3 $4" == "secrets versions access latest" ]]; then
    printf 'mock-gcp-secret-value'
    exit 0
fi
printf 'unexpected gcloud command: %s\n' "$*" >&2
exit 2
SH
chmod +x "$temp_dir/bin/gcloud"

export PATH="$temp_dir/bin:$PATH"
export PORTMASON_SHARE="$source_dir"
export SCRIPT_DIR="$temp_dir/project"
export ENV_FILE="$temp_dir/project/.env"
export RUNTIME_ADAPTER_CODE=node-azure
export DB_PROVIDER_PLATFORM_CODE=postgres-neon
export DEPLOY_ENV=prd
export STACK=test-prd
export PROJECT_ID=test-azure-project
export DEPLOYMENT_ID=test-azure-project
export SECRET_PATHS='DB_API_KEY|github:TEST_ROUTED_SECRET'
export TEST_ROUTED_SECRET=mock-gcp-secret-value
export IN_CONTAINER=false

log() { :; }
die() { printf 'ERROR: %s\n' "${1:-unknown}" >&2; return "${2:-1}"; }
export -f log die

cd "$temp_dir/project"

# shellcheck disable=SC1091
. "$source_dir/pm-helpers"

value="$(get_secret 'github:TEST_ROUTED_SECRET')"
[[ "$value" == "mock-gcp-secret-value" ]]

path="$(get_secret_path_by_ref DB_API_KEY)"
[[ "$path" == 'github:TEST_ROUTED_SECRET' ]]
# A SECRET_PATHS binding is authoritative. The conflicting plaintext value
# loaded from .env must never override the configured secret provider.
pm_config_value resolved DB_API_KEY
[[ "$resolved" == "mock-gcp-secret-value" ]]

DB_API_KEY=secret
pm_secret_resolve_value resolved DB_API_KEY "$DB_API_KEY"
[[ "$resolved" == "mock-gcp-secret-value" ]]
pm_config_value resolved DB_API_KEY
[[ "$resolved" == "mock-gcp-secret-value" ]]

TEST_ROUTED_SECRET=mock-routed-secret \
ROUTED_VALUE=secret \
    python3 "$source_dir/pm-secret.py" run-with-secrets \
        --secret-env 'ROUTED_VALUE|github:TEST_ROUTED_SECRET' \
        -- bash -c '[[ "$ROUTED_VALUE" == "mock-routed-secret" ]]'



# shellcheck disable=SC1091
. "$source_dir/pm-helpers-neon"
unset DB_API_KEY DB_API_KEY_PATH
neon_sync_control_secret
[[ "$DB_API_KEY" == "mock-gcp-secret-value" ]]

printf 'PASS: secret provider dispatch follows path prefix independent of runtime adapter\n'

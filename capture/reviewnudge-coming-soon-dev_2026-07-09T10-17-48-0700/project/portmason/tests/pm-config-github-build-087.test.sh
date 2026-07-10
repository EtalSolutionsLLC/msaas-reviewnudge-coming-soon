#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PORTMASON_SHARE="$(cd -- "${TEST_DIR}/.." && pwd -P)"
export PORTMASON_SHARE
TMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TMP_DIR"' EXIT INT TERM
mkdir -p "$TMP_DIR/bin" "$TMP_DIR/site"

cat >"$TMP_DIR/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >>"${MOCK_GH_TRACE:?}"
printf '\n' >>"${MOCK_GH_TRACE:?}"
if [[ "${1:-} ${2:-}" == "secret set" ]]; then
    cat >>"${MOCK_GH_SECRET_BODY:?}"
fi
GH
chmod +x "$TMP_DIR/bin/gh"
export PATH="$TMP_DIR/bin:$PATH"
export MOCK_GH_TRACE="$TMP_DIR/gh.trace"
export MOCK_GH_SECRET_BODY="$TMP_DIR/gh.secret"

SCRIPT_DIR="$TMP_DIR"
PROJECT_ROOT="$TMP_DIR"
ENV_FILE="$TMP_DIR/.env"
export SCRIPT_DIR PROJECT_ROOT ENV_FILE
: >"$ENV_FILE"

log() { :; }
warn() { :; }
die() { printf 'ERROR: %s\n' "${1:-unknown error}" >&2; return "${2:-1}"; }
have() { command -v "$1" >/dev/null 2>&1; }
env_file_to_kv_nul() { :; }
pm_compose_load_model() { :; }
export -f log warn die have env_file_to_kv_nul pm_compose_load_model

# shellcheck disable=SC1091
. "${PORTMASON_SHARE}/pm-helpers-config"
# shellcheck disable=SC1091
. "${PORTMASON_SHARE}/pm-config-manager"

export PM_CONFIG_STRICT=true
export RUNTIME_ADAPTER_CODE=static-github
export DEPLOY_ENV=prd
export STACK=static-prd
export PROJECT_ID=static-project
export DEPLOYMENT_ID=static-deployment
export APP_SLUG=static-site
export APP_HOST=www.example.test
export APP_URL=https://www.example.test
export LOG_LEVEL=info
export APP_SECRET='github-actions-only-secret'
export PM_GITHUB_REPOSITORY=example/site
export PM_GITHUB_SYNC_ACTIONS_CONFIG=true
export GITHUB_PAGES_BUILD_DIR="$TMP_DIR/site"
export GITHUB_PAGES_CONFIG_JSON="$TMP_DIR/site/config.generated.json"

PM_COMPOSE_MODEL_JSON='{"services":{"web":{"labels":{"solutions.etal.service":"web","solutions.etal.config_scopes":"routing,application,web,static,observability"}}}}'
PROJECT_SERVICES='[{"service":"web","role":"web","image":"","has_build":true}]'
export PM_COMPOSE_MODEL_JSON PROJECT_SERVICES

pm_config_manager_apply

config="$GITHUB_PAGES_CONFIG_JSON"
[[ -f "$config" ]] || { printf 'FAIL: browser config was not written\n' >&2; exit 1; }
jq -e '.APP_URL == "https://www.example.test"' "$config" >/dev/null
if grep -Fq 'github-actions-only-secret' "$config"; then
    printf 'FAIL: secret leaked into public browser config\n' >&2
    exit 1
fi

grep -Fq 'variable set APP_URL' "$MOCK_GH_TRACE"
grep -Fq 'secret set APP_SECRET' "$MOCK_GH_TRACE"
if grep -Fq 'github-actions-only-secret' "$MOCK_GH_TRACE"; then
    printf 'FAIL: GitHub secret was passed in command arguments\n' >&2
    exit 1
fi
[[ "$(cat "$MOCK_GH_SECRET_BODY")" == 'github-actions-only-secret' ]] || {
    printf 'FAIL: GitHub secret was not supplied through stdin\n' >&2
    exit 1
}

printf 'PASS: GitHub public config and Actions secret separation\n'

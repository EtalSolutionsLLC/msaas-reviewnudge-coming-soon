#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PORTMASON_SHARE="$(cd -- "${TEST_DIR}/.." && pwd -P)"
export PORTMASON_SHARE
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
SCRIPT_DIR="$TMP_DIR"
PROJECT_ROOT="$TMP_DIR"
ENV_FILE="$TMP_DIR/.env"
export SCRIPT_DIR PROJECT_ROOT ENV_FILE
: >"$ENV_FILE"

log() { :; }
warn() { :; }
die() { printf 'ERROR: %s\n' "${1:-unknown}" >&2; return "${2:-1}"; }
have() { command -v "$1" >/dev/null 2>&1; }
env_file_to_kv_nul() { :; }
pm_preflight_has_secret_override() { return 1; }

# shellcheck disable=SC1091
. "${PORTMASON_SHARE}/pm-helpers-config"
# shellcheck disable=SC1091
. "${PORTMASON_SHARE}/pm-config-manager"

export PM_CONFIG_STRICT=true
export RUNTIME_ADAPTER_CODE=node-gcp
export DB_PROVIDER_PLATFORM_CODE=postgres-gcp
export PM_SUPPORT_CHANNEL_PROVIDER=slack
export STACK=test-dev
export DEPLOYMENT_ID=test-project
export REGION=us-central1
export DEPLOY_ENV=prd
export APP_SLUG=test
export PROJECT_ID=test-project
export DB_NAME=reviewnudge
export DB_USER=reviewnudge_app
export DB_PASSWORD='db-test-secret'
export PM_SUPPORT_CHANNEL_BOT_TOKEN='support-bot-test-secret'
export PM_SUPPORT_CHANNEL_SOCKET_TOKEN='support-socket-test-secret'

PM_COMPOSE_MODEL_JSON='{
  "services": {
    "web": {"labels":{"solutions.etal.service":"web","solutions.etal.config_scopes":"application,database"}},
    "support-bot": {"labels":{"solutions.etal.service":"worker","solutions.etal.config_scopes":"pm-support-channel"}}
  }
}'
PROJECT_SERVICES='[
  {"service":"web","role":"web","image":"web:test","has_build":true},
  {"service":"support-bot","role":"worker","image":"bot:test","has_build":true}
]'
export PM_COMPOSE_MODEL_JSON PROJECT_SERVICES

pm_config_manager_prepare gcp
# shellcheck disable=SC1091
. "${PORTMASON_SHARE}/pm-helpers-gcp-secrets"

support_args="$(pm_gcp_secret_args_for_service support-bot worker | tr '\0' '\n')"
web_args="$(pm_gcp_secret_args_for_service web web | tr '\0' '\n')"

grep -Fq 'SUPPORT_CHANNEL_BOT_TOKEN=projects/test-project/secrets/test-dev-pm-support-channel-bot-token:latest' <<<"$support_args"
grep -Fq 'SUPPORT_CHANNEL_SOCKET_TOKEN=projects/test-project/secrets/test-dev-pm-support-channel-socket-token:latest' <<<"$support_args"
if grep -Fq 'DB_PASSWORD=' <<<"$support_args"; then
    printf 'FAIL: DB secret was injected into support-bot\n' >&2
    exit 1
fi

grep -Fq 'DB_PASSWORD=projects/test-project/secrets/test-dev-db-password:latest' <<<"$web_args"
if grep -Fq 'SUPPORT_CHANNEL_BOT_TOKEN=' <<<"$web_args"; then
    printf 'FAIL: support secret was injected into web\n' >&2
    exit 1
fi

printf 'PASS: GCP service-specific secret bindings use PM Configuration Manager scopes\n'

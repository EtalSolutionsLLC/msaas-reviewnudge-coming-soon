#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PORTMASON_SHARE="$(cd -- "${TEST_DIR}/.." && pwd -P)"
export PORTMASON_SHARE

bash -n \
    "${PORTMASON_SHARE}/pm-config-azure" \
    "${PORTMASON_SHARE}/pm-helpers-azure" \
    "${PORTMASON_SHARE}/pm-provision-azure" \
    "${PORTMASON_SHARE}/pm-deploy-azure" \
    "${PORTMASON_SHARE}/pm-db-bridge-postgres-azure"

grep -Fq 'pm_adapter_requires_compose' "${PORTMASON_SHARE}/pm-helpers-azure"
grep -Fq 'pm_azure_cli()' "${PORTMASON_SHARE}/pm-helpers-azure"
grep -Fq 'PM_AZURE_CLI_USE_WINDOWS' "${PORTMASON_SHARE}/pm-helpers-azure"
grep -Fq 'az.cmd' "${PORTMASON_SHARE}/pm-helpers-azure"
grep -Fq 'keyvaultref:' "${PORTMASON_SHARE}/pm-helpers-azure"
grep -Fq 'identityref:' "${PORTMASON_SHARE}/pm-helpers-azure"
grep -Fq 'secretref:' "${PORTMASON_SHARE}/pm-helpers-azure"
grep -Fq 'pm_azure_cli containerapp create' "${PORTMASON_SHARE}/pm-deploy-azure"
grep -Fq 'pm_azure_cli containerapp job "$action"' "${PORTMASON_SHARE}/pm-deploy-azure"
grep -Fq 'pm_azure_cli postgres flexible-server create' "${PORTMASON_SHARE}/pm-provision-azure"
grep -Fq 'PGSSLMODE=require' "${PORTMASON_SHARE}/pm-db-bridge-postgres-azure"

if grep -Eq '(^|[[:space:]])az[[:space:]]+(account|acr|containerapp|group|identity|keyvault|postgres|provider|role|servicebus)' \
    "${PORTMASON_SHARE}/pm-helpers-azure" \
    "${PORTMASON_SHARE}/pm-provision-azure" \
    "${PORTMASON_SHARE}/pm-deploy-azure"; then
    printf 'FAIL: Azure adapter bypasses pm_azure_cli wrapper.\n' >&2
    exit 1
fi

if grep -Eq 'case "\$\{ADAPTER_CODE:-\}"|local\|gcp|gcp\|azure|azure\|aws|gcp\|aws' \
    "${PORTMASON_SHARE}/pm-helpers-db"; then
    printf 'FAIL: pm-helpers-db still contains provider-specific adapter branching.\n' >&2
    exit 1
fi

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
env_init_set() {
    local key="${1:?key required}" value="${2-}"
    printf -v "$key" '%s' "$value"
    export "$key"
}
pm_preflight_has_secret_override() { return 1; }
env_file_to_kv_nul() { :; }

# shellcheck disable=SC1091
. "${PORTMASON_SHARE}/pm-helpers-config"
# shellcheck disable=SC1091
. "${PORTMASON_SHARE}/pm-config-manager"
# shellcheck disable=SC1091
. "${PORTMASON_SHARE}/pm-helpers-azure"

export PM_CONFIG_STRICT=true
export RUNTIME_ADAPTER_CODE=node-azure
export DB_PROVIDER_PLATFORM_CODE=postgres-azure
export DB_PROVIDER_CODE=postgres
export DB_PLATFORM_CODE=azure
export STACK=test-dev
export DEPLOYMENT_ID=test-project
export DEPLOY_ENV=dev
export APP_SLUG=test
export PROJECT_ID=test-project
export DB_NAME=reviewnudge
export DB_HOST=test-pg.postgres.database.azure.com
export DB_PORT=5432
export DB_USER=reviewnudge_app
export DB_PASSWORD='db-test-secret'
export APP_SECRET='app-test-secret'
export PLATFORM_REGION=centralus
export AZURE_RESOURCE_GROUP=test-rg
export AZURE_KEYVAULT_NAME=test-kv
export AZURE_IDENTITY_ID='/subscriptions/000/resourceGroups/test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/test-id'
export AZURE_SERVICE_BUS_NAMESPACE=test-sb

pm_azure_defaults
[[ "$AZURE_LOCATION" == "centralus" ]]
[[ "$PLATFORM_REGION" == "centralus" ]]

PM_COMPOSE_MODEL_JSON='{
  "services": {
    "web": {"labels":{"solutions.etal.service":"web","solutions.etal.config_scopes":"application,database"}},
    "worker": {"labels":{"solutions.etal.service":"worker","solutions.etal.config_scopes":"application"}}
  }
}'
PROJECT_SERVICES='[
  {"service":"web","role":"web","image":"web:test","has_build":true},
  {"service":"worker","role":"worker","image":"worker:test","has_build":true,"queue_consume":"jobs"},
  {"service":"jobs","role":"queue","image":"rabbitmq:test","has_build":false,"queue_delivery":"immediate,scheduled"}
]'
export PM_COMPOSE_MODEL_JSON PROJECT_SERVICES

pm_config_manager_prepare azure

web_secrets="$(secret_args_for_service web web | tr '\0' '\n')"
web_env="$(env_args_for_service web web | tr '\0' '\n')"
worker_env="$(env_args_for_service worker worker | tr '\0' '\n')"

grep -Fq 'keyvaultref:https://test-kv.vault.azure.net/secrets/test-dev-db-password' <<<"$web_secrets"
grep -Fq 'identityref:/subscriptions/000/resourceGroups/test-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/test-id' <<<"$web_secrets"
grep -Eq '^DB_PASSWORD=secretref:s-[a-f0-9]{10}' <<<"$web_env"
grep -Fq 'PM_QUEUE_PROVIDER=service-bus' <<<"$worker_env"
grep -Fq 'PM_QUEUE_NAMESPACE=test-sb' <<<"$worker_env"
grep -Fq 'PM_QUEUE_NAME=jobs' <<<"$worker_env"
grep -Fq 'PM_SCHEDULED_WORK_PROVIDER=service-bus' <<<"$worker_env"
grep -Fq 'PM_SCHEDULED_WORK_NAMESPACE=test-sb' <<<"$worker_env"
grep -Fq 'PM_SCHEDULED_WORK_QUEUE=jobs' <<<"$worker_env"

if grep -Fq 'db-test-secret' <<<"$web_secrets$web_env"; then
    printf 'FAIL: Azure injection exposed a raw secret value.\n' >&2
    exit 1
fi

printf 'PASS: Azure adapter contract uses DI hooks, Key Vault refs, and Service Bus queue env\n'

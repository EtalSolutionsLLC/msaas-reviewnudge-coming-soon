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
die() {
    printf 'ERROR: %s\n' "${1:-unknown error}" >&2
    return "${2:-1}"
}
env_file_to_kv_nul() { :; }
pm_compose_load_model() { :; }

# shellcheck disable=SC1091
. "${PORTMASON_SHARE}/pm-helpers-config"
# shellcheck disable=SC1091
. "${PORTMASON_SHARE}/pm-config-manager"

export PM_CONFIG_STRICT=true
export RUNTIME_ADAPTER_CODE=node-local
export DB_PROVIDER_PLATFORM_CODE=postgres-local
export PM_SUPPORT_CHANNEL_PROVIDER=slack
export PM_EDGE_TUNNEL_PROVIDER=cloudflared
export PM_ACME_DNS_PROVIDER=godaddy
export PM_CONFIG_ENTITIES=traefik

export STACK=test-dev
export PROJECT_ID=test-project
export DEPLOYMENT_ID=test-deployment
export APP_SLUG=test
export DEPLOY_ENV=dev
export APP_HOST=test.localtest.me
export APP_URL=https://test.localtest.me
export LOG_LEVEL=debug
export LOG_FORMAT=text
export NODE_ENV=development
export PORT=8080

export DB_NAME=reviewnudge
export DB_USER=reviewnudge_app
export DB_PASSWORD='db-test-secret'
export APP_SECRET='app-test-secret'
export PM_SUPPORT_CHANNEL_BOT_TOKEN='support-bot-test-secret'
export PM_SUPPORT_CHANNEL_SOCKET_TOKEN='support-socket-test-secret'
export PM_EDGE_TUNNEL_TOKEN='tunnel-test-secret'
export PM_ACME_DNS_API_KEY='dns-key-test-secret'
export PM_ACME_DNS_API_SECRET='dns-secret-test-secret'
export PM_TRAEFIK_LOG_LEVEL=INFO

PM_COMPOSE_MODEL_JSON='{
  "services": {
    "web": {"labels":{"solutions.etal.service":"web","solutions.etal.config_scopes":"application,database,observability"}},
    "support-bot": {"labels":{"solutions.etal.service":"worker","solutions.etal.config_scopes":"pm-support-channel"}},
    "cloudflared": {"labels":{"solutions.etal.service":"proxy","solutions.etal.config_scopes":"pm-edge-tunnel"}},
    "traefik": {"labels":{"solutions.etal.service":"proxy","solutions.etal.config_scopes":"pm-edge-ingress,pm-acme-dns"}},
    "db": {"labels":{"solutions.etal.service":"db","solutions.etal.config_scopes":"database,database-admin"}}
  }
}'
PROJECT_SERVICES='[
  {"service":"web","role":"web","image":"web:test","has_build":true},
  {"service":"support-bot","role":"worker","image":"bot:test","has_build":true},
  {"service":"cloudflared","role":"proxy","image":"cloudflare/cloudflared:test","has_build":false},
  {"service":"traefik","role":"proxy","image":"traefik:test","has_build":false},
  {"service":"db","role":"db","image":"postgres:test","has_build":false}
]'
export PM_COMPOSE_MODEL_JSON PROJECT_SERVICES

assert_file_contains() {
    local file="${1:?file required}"
    local value="${2:?value required}"
    grep -Fq -- "$value" "$file" || {
        printf 'FAIL: %s does not contain %s\n' "$file" "$value" >&2
        exit 1
    }
}

assert_file_not_contains() {
    local file="${1:?file required}"
    local value="${2:?value required}"
    if grep -Fq -- "$value" "$file"; then
        printf 'FAIL: %s unexpectedly contains %s\n' "$file" "$value" >&2
        exit 1
    fi
}

pm_config_manager_apply

web_file="$TMP_DIR/.portmason/config/web.env"
support_file="$TMP_DIR/.portmason/config/support-bot.env"
tunnel_file="$TMP_DIR/.portmason/config/cloudflared.env"
traefik_file="$TMP_DIR/.portmason/config/traefik.env"
db_file="$TMP_DIR/.portmason/config/db.env"
manifest="$TMP_DIR/.portmason/config/manifest.tsv"

for file in "$web_file" "$support_file" "$tunnel_file" "$traefik_file" "$db_file" "$manifest"; do
    [[ -f "$file" ]] || { printf 'FAIL: missing %s\n' "$file" >&2; exit 1; }
done

assert_file_contains "$web_file" "DB_PASSWORD='db-test-secret'"
assert_file_contains "$web_file" "APP_SECRET='app-test-secret'"
assert_file_not_contains "$web_file" 'SUPPORT_CHANNEL_BOT_TOKEN'
assert_file_not_contains "$web_file" 'TUNNEL_TOKEN'

assert_file_contains "$support_file" "SUPPORT_CHANNEL_BOT_TOKEN='support-bot-test-secret'"
assert_file_contains "$support_file" "SUPPORT_CHANNEL_SOCKET_TOKEN='support-socket-test-secret'"
assert_file_not_contains "$support_file" 'DB_PASSWORD'
assert_file_not_contains "$support_file" 'APP_SECRET'

assert_file_contains "$tunnel_file" "TUNNEL_TOKEN='tunnel-test-secret'"
assert_file_not_contains "$tunnel_file" 'DB_PASSWORD'
assert_file_not_contains "$tunnel_file" 'GODADDY_API_KEY'

assert_file_contains "$traefik_file" "TRAEFIK_LOG_LEVEL='INFO'"
assert_file_contains "$traefik_file" "GODADDY_API_KEY='dns-key-test-secret'"
assert_file_contains "$traefik_file" "GODADDY_API_SECRET='dns-secret-test-secret'"
assert_file_not_contains "$traefik_file" 'TUNNEL_TOKEN'

assert_file_contains "$db_file" "DB_NAME='reviewnudge'"
assert_file_contains "$db_file" "DB_USER='reviewnudge_app'"
assert_file_contains "$db_file" "DB_PASSWORD='db-test-secret'"
assert_file_not_contains "$db_file" 'APP_SECRET'

[[ "$(stat -c '%a' "$support_file")" == 600 ]] || {
    printf 'FAIL: service env file permissions are not 600\n' >&2
    exit 1
}

assert_file_contains "$manifest" $'support-bot\tworker\tpm-support-channel'
assert_file_not_contains "$manifest" 'support-bot-test-secret'

plan_output="$(pm_config_manager_plan)"
grep -Fq $'PM_EDGE_TUNNEL_TOKEN\tsecret\tpm-edge-tunnel,cloudflared\tTUNNEL_TOKEN' <<<"$plan_output"
if grep -Fq 'tunnel-test-secret' <<<"$plan_output"; then
    printf 'FAIL: plan leaked a secret value\n' >&2
    exit 1
fi

# Required values fail before any adapter apply when the matching service asks
# for that configuration scope.
unset PM_EDGE_TUNNEL_TOKEN
if (pm_config_manager_prepare apply >/dev/null 2>&1); then
    printf 'FAIL: missing required tunnel token was accepted\n' >&2
    exit 1
fi

printf 'PASS: PM Configuration Manager registry, scoping, aliases, and local injection\n'

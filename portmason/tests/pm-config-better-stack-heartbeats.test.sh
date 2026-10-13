#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

die() {
    printf 'ERROR: %s\n' "${1:-unknown error}" >&2
    return "${2:-1}"
}

# shellcheck disable=SC1091
. "$root/pm-helpers-config"
# shellcheck disable=SC1091
. "$root/pm-config-application"

pm_config_application

export MONITORING_HEARTBEAT_OUTBOUND_COMMUNICATIONS_TOKEN_SECURED_URL='https://uptime.betterstack.com/api/v1/heartbeat/outbound-test'
export MONITORING_HEARTBEAT_EXTERNAL_SYNC_TOKEN_SECURED_URL='https://uptime.betterstack.com/api/v1/heartbeat/external-sync-test'
export MONITORING_HEARTBEAT_HOUSEKEEPING_TOKEN_SECURED_URL='https://uptime.betterstack.com/api/v1/heartbeat/housekeeping-test'
export MONITORING_FAILURE_EVENT_HTTP_ENDPOINT='https://failure-events.example.test/'
export MONITORING_FAILURE_EVENT_HTTP_TIMEOUT_MS='1500'
export SECRET_PATHS='MONITORING_FAILURE_EVENT_HTTP_BEARER_TOKEN|gcp:central-failure-event-token'

worker_bindings="$(pm_config_secret_binding_nul_for_service worker worker | tr '\0' '\n')"
web_bindings="$(pm_config_secret_binding_nul_for_service web web | tr '\0' '\n')"
worker_vars="$(pm_config_keys_for_scopes var worker)"
web_vars="$(pm_config_keys_for_scopes var web)"

for key in \
    MONITORING_HEARTBEAT_OUTBOUND_COMMUNICATIONS_TOKEN_SECURED_URL \
    MONITORING_HEARTBEAT_EXTERNAL_SYNC_TOKEN_SECURED_URL \
    MONITORING_HEARTBEAT_HOUSEKEEPING_TOKEN_SECURED_URL; do
    grep -Fxq "$key" <<<"$worker_bindings" || {
        printf 'FAIL: worker is missing %s\n' "$key" >&2
        exit 1
    }
    if grep -Fxq "$key" <<<"$web_bindings"; then
        printf 'FAIL: web unexpectedly receives %s\n' "$key" >&2
        exit 1
    fi
done

for bindings in "$worker_bindings" "$web_bindings"; do
    grep -Fxq MONITORING_FAILURE_EVENT_HTTP_BEARER_TOKEN <<<"$bindings" || {
        printf 'FAIL: application service is missing MONITORING_FAILURE_EVENT_HTTP_BEARER_TOKEN\n' >&2
        exit 1
    }
done

for vars in "$worker_vars" "$web_vars"; do
    grep -Fxq MONITORING_FAILURE_EVENT_HTTP_ENDPOINT <<<"$vars" || {
        printf 'FAIL: application service is missing MONITORING_FAILURE_EVENT_HTTP_ENDPOINT\n' >&2
        exit 1
    }
    grep -Fxq MONITORING_FAILURE_EVENT_HTTP_TIMEOUT_MS <<<"$vars" || {
        printf 'FAIL: application service is missing MONITORING_FAILURE_EVENT_HTTP_TIMEOUT_MS\n' >&2
        exit 1
    }
done

printf 'PASS: Better Stack heartbeats and runtime-neutral failure events are scoped correctly\n'

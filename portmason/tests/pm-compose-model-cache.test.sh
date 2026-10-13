#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
log() { :; }
die() { return "${2:-1}"; }
have() { command -v "$1" >/dev/null 2>&1; }
env_init_set() { printf -v "$1" '%s' "${2-}"; export "$1"; }
export PORTMASON_SHARE="$root"
source "$root/pm-helpers-db"

rendered_model='{"services":{"web":{"image":"app:test","labels":{"solutions.etal.service":"web"}}}}'
pm_compose_init_command() { PM_COMPOSE_CMD=(true); }
pm_compose_render_json() {
    printf '%s\n' 'warning: optional variable is unset' >&2
    printf '%s' "$rendered_model"
}

PM_COMPOSE_MODEL_JSON='{"services":{}}'
PROJECT_SERVICES='[]'
export PM_COMPOSE_MODEL_JSON PROJECT_SERVICES

pm_compose_load_model
[[ "$(jq -r '.[0].service' <<<"$PROJECT_SERVICES")" == "web" ]]
[[ "$(jq -r '.[0].role' <<<"$PROJECT_SERVICES")" == "web" ]]

ADAPTER_CODE=gcp
PM_COMPOSE_PREFLIGHT=auto
pm_compose_preflight_required
grep -Fq 'refusing false-success deployment' "$root/pm-deploy-gcp"
grep -Fq 'sort_by(if .has_build then 0 else 1 end)' "$root/pm-helpers-db"
grep -Fq 'resource="$secret"' "$root/pm-helpers-gcp-secrets"
grep -Fq 'K_CONFIGURATION)(=|:[[:space:]])' "$root/pm-deploy-gcp"
grep -Fq 'if [[ "${BASH_SOURCE[0]}" == "$0" ]]' "$root/pm-deploy-gcp"
grep -Fq 'inherit only the portable run-once command metadata' "$root/pm-deploy-gcp"

echo "PASS: cached Compose model rebuilds project services"

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
RUNTIME_ADAPTER_CODE=traefik-local
export SCRIPT_DIR PROJECT_ROOT ENV_FILE RUNTIME_ADAPTER_CODE
: >"$ENV_FILE"

log() { :; }
warn() { :; }
die() {
    printf 'ERROR: %s\n' "${1:-unknown error}" >&2
    return "${2:-1}"
}
env_file_to_kv_nul() { :; }

# shellcheck disable=SC1091
. "${PORTMASON_SHARE}/pm-helpers-config"
# shellcheck disable=SC1091
. "${PORTMASON_SHARE}/pm-config-manager"

cat >"$TMP_DIR/docker-compose.yml" <<'YAML'
services:
  cloudflared:
    env_file:
      - ./.portmason/config/cloudflared.env
  traefik:
    env_file:
      - path: ./.portmason/config/traefik.env
  ignored:
    env_file:
      - ./operator.env
YAML

mkdir -p "$TMP_DIR/.portmason/config"
printf 'PRESERVE=1\n' >"$TMP_DIR/.portmason/config/cloudflared.env"
chmod 600 "$TMP_DIR/.portmason/config/cloudflared.env"

pm_config_manager_bootstrap_local_env_files

traefik_env="$TMP_DIR/.portmason/config/traefik.env"
cloudflared_env="$TMP_DIR/.portmason/config/cloudflared.env"
[[ -f "$traefik_env" ]] || {
    printf 'FAIL: missing bootstrap Traefik service env\n' >&2
    exit 1
}
[[ "$(cat "$cloudflared_env")" == 'PRESERVE=1' ]] || {
    printf 'FAIL: bootstrap overwrote an existing service env\n' >&2
    exit 1
}
[[ "$(stat -c '%a' "$traefik_env")" == 600 ]] || {
    printf 'FAIL: bootstrap env permissions are not 600\n' >&2
    exit 1
}
[[ "$(stat -c '%a' "$TMP_DIR/.portmason/config")" == 700 ]] || {
    printf 'FAIL: bootstrap directory permissions are not 700\n' >&2
    exit 1
}
[[ ! -e "$TMP_DIR/operator.env" ]] || {
    printf 'FAIL: bootstrap created a non-Portmason env file\n' >&2
    exit 1
}

after_first="$(stat -c '%Y:%s' "$traefik_env")"
pm_config_manager_bootstrap_local_env_files
[[ "$(stat -c '%Y:%s' "$traefik_env")" == "$after_first" ]] || {
    printf 'FAIL: idempotent bootstrap changed an existing placeholder\n' >&2
    exit 1
}

rm -f "$traefik_env"
pm_compose_load_model() {
    [[ -f "$traefik_env" ]] || return 9
    PM_COMPOSE_MODEL_JSON='{"services":{"traefik":{"labels":{"solutions.etal.service":"proxy"}}}}'
    PROJECT_SERVICES='[{"service":"traefik","role":"proxy","image":"traefik:test","has_build":false}]'
    export PM_COMPOSE_MODEL_JSON PROJECT_SERVICES
}
pm_config_manager_ensure_compose_model
[[ -f "$traefik_env" ]] || {
    printf 'FAIL: compose model bootstrap did not create required env file\n' >&2
    exit 1
}

rm -f "$traefik_env"
RUNTIME_ADAPTER_CODE=traefik-gcp
export RUNTIME_ADAPTER_CODE
pm_config_manager_bootstrap_local_env_files
[[ ! -e "$traefik_env" ]] || {
    printf 'FAIL: non-local adapter created local service env placeholder\n' >&2
    exit 1
}

setup_file="${PORTMASON_SHARE}/pm-setup"
helpers_db="${PORTMASON_SHARE}/pm-helpers-db"
bootstrap_line="$(grep -n 'pm_config_manager_bootstrap_local_env_files' "$setup_file" | head -n1 | cut -d: -f1)"
refresh_line="$(grep -n 'pm_setup_refresh_generated_environment' "$setup_file" | tail -n1 | cut -d: -f1)"
config_line="$(grep -n 'pm_config_manager_apply' "$setup_file" | head -n1 | cut -d: -f1)"
setup_line="$(grep -n 'pm_setup_run_runtime_setup_modules' "$setup_file" | tail -n1 | cut -d: -f1)"
provision_line="$(grep -n 'pm_db_run_provision' "$setup_file" | tail -n1 | cut -d: -f1)"

[[ "$bootstrap_line" -lt "$refresh_line" ]] || {
    printf 'FAIL: local env bootstrap must precede runtime selector refresh\n' >&2
    exit 1
}
[[ "$provision_line" -lt "$config_line" ]] || {
    printf 'FAIL: configuration apply must follow database provisioning\n' >&2
    exit 1
}
[[ "$config_line" -lt "$setup_line" ]] || {
    printf 'FAIL: configuration apply must precede runtime setup\n' >&2
    exit 1
}

preflight_bootstrap_line="$(grep -n 'pm_config_manager_bootstrap_local_env_files' "$helpers_db" | tail -n1 | cut -d: -f1)"
preflight_compose_line="$(grep -n 'pm_compose_load_model || true' "$helpers_db" | head -n1 | cut -d: -f1)"
[[ "$preflight_bootstrap_line" -lt "$preflight_compose_line" ]] || {
    printf 'FAIL: preflight must bootstrap generated env files before Compose render\n' >&2
    exit 1
}

printf 'PASS: PM Configuration Manager bootstraps Compose env files before model inspection and runtime setup\n'

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PROJECT_ROOT="$TMP_DIR/project"
REPO_ROOT="$PROJECT_ROOT"
PORTMASON_SHARE="$ROOT"
PORTMASON_PROJECT_ROOT="$PROJECT_ROOT"
ENV_FILE="$PROJECT_ROOT/.env"
DEPLOY_ENV=prd
IN_CONTAINER=false
RUNTIME_ADAPTER_CODE=node-gcp
ADAPTER_CODE=gcp
mkdir -p "$PROJECT_ROOT"
printf 'APP_SLUG=test\nDEPLOY_ENV=prd\n' >"$ENV_FILE"
export PROJECT_ROOT REPO_ROOT PORTMASON_SHARE PORTMASON_PROJECT_ROOT ENV_FILE DEPLOY_ENV
export IN_CONTAINER RUNTIME_ADAPTER_CODE ADAPTER_CODE

log() { :; }
warn() { :; }
die() {
    printf 'ERROR: %s\n' "${1:-unknown error}" >&2
    return "${2:-1}"
}

# shellcheck source=/dev/null
. "$ROOT/pm-helpers" --read-only

PM_STAGE_PORTMASON=auto
export PM_STAGE_PORTMASON
! pm_portmason_staging_required

PM_STAGE_PORTMASON=always
export PM_STAGE_PORTMASON
pm_portmason_staging_required

PM_STAGE_PORTMASON=never
export PM_STAGE_PORTMASON
! pm_portmason_staging_required

PM_STAGE_PORTMASON=auto
ADAPTER_CODE=local
LOCAL_EXEC_MODE=container
export PM_STAGE_PORTMASON ADAPTER_CODE LOCAL_EXEC_MODE
pm_portmason_staging_required

ADAPTER_CODE=gcp
unset LOCAL_EXEC_MODE
cat >"$PROJECT_ROOT/docker-compose.yml" <<'YAML'
services:
  app:
    volumes:
      - ./portmason:/opt/portmason:ro
  logs:
    volumes:
      - ./logs/runtime:/var/log/portmason
YAML
export ADAPTER_CODE
pm_portmason_staging_required

cat >"$PROJECT_ROOT/docker-compose.yml" <<'YAML'
services:
  logs:
    volumes:
      - ./logs/runtime:/var/log/portmason
YAML
! pm_portmason_staging_required

grep -Fq 'pm_portmason_staging_required' "$ROOT/pm-setup"
grep -Fq 'Portmason runtime staging skipped' "$ROOT/pm-setup"

printf 'PASS: Portmason staging policy favors skip unless staging is required\n'

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
ENTRY="$ROOT/pm-setup-observability"
HELPERS="$ROOT/pm-helpers-observability"

bash -n "$ENTRY" "$HELPERS" "$ROOT/pm-observability-status"
grep -Fq '. "${PORTMASON_SHARE}/pm-helpers" "$@"' "$ENTRY"

! grep -Eqi 'observability' "$ROOT/pm-setup"
! grep -Eqi 'observability' "$ROOT/pm-deploy-local"

grep -Fq '${ENV_FILE:?ENV_FILE required}.generated' "$HELPERS"
grep -Fq 'docker-compose.observability.yml' "$ENTRY" "$HELPERS"
! grep -Fq 'docker-compose.observability.yml' "$ENTRY" "$HELPERS"
grep -Fq 'pm_run_observability_dependency provision store' "$ENTRY"
grep -Fq 'pm_observability_local_compose up -d --pull missing --remove-orphans --wait' \
  "$ROOT/pm-deploy-observability-store-local"
grep -Fq 'required="$(pm_observability_local_compose config --services)"' \
  "$ROOT/pm-deploy-observability-store-local"
! grep -Fq 'OBSERVABILITY_OTLP_PLATFORM' "$ENTRY"
! grep -Eq 'pm_run_observability_dependency.*collector' "$ENTRY"
grep -Fq 'Telemetry dashboard did not become ready within 60 seconds' \
  "$ROOT/pm-deploy-observability-store-local"
! grep -Eq '(^|[[:space:]])(stop|down)([|)])' "$ENTRY" "$HELPERS"
! grep -Eq 'RUNTIME_[A-Z_]*|DB_PROVIDER|DB_PLATFORM' "$ENTRY"
! grep -Fq 'OBSERVABILITY_DB_ENABLED' "$HELPERS"
! grep -Fq 'PM_OBSERVABILITY_STORE_ENABLED' "$HELPERS"

grep -Fq 'OBSERVABILITY_ENABLED' "$HELPERS"
grep -Fq 'OBSERVABILITY_STORE_PROVIDER_PLATFORM_CODE is required when observability is enabled' "$HELPERS"
grep -Fq 'OBSERVABILITY_DASHBOARD_ENABLED' "$ENTRY"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT INT TERM
git -C "$tmp" init -q
mkdir -p "$tmp/deploy/prd"
printf '%s\n' '1778712786' >"$tmp/.project_timestamp"
printf '%s\n' \
  'APP_SLUG=sample' \
  'DEPLOY_ENV=dev' \
  'STACK=${APP_SLUG}-${DEPLOY_ENV}' \
  'APP_URL=https://${STACK}.example.test' \
  'OBSERVABILITY_ENABLED=false' >"$tmp/.env"
printf '%s\n' \
  'APP_SLUG=sample' \
  'DEPLOY_ENV=prd' \
  'STACK=${APP_SLUG}-${DEPLOY_ENV}' \
  'APP_URL=https://${STACK}.example.test' \
  'OBSERVABILITY_ENABLED=false' >"$tmp/deploy/prd/.env"

root_context="$(cd -- "$tmp" && PORTMASON_SHARE="$ROOT" "$ENTRY" --bootstrap-context)"
deploy_context="$(cd -- "$tmp/deploy/prd" && PORTMASON_SHARE="$ROOT" "$ENTRY" --bootstrap-context)"
[[ -s "$tmp/.env.generated" ]]
[[ -s "$tmp/config.generated.json" ]]
grep -Fq "SCRIPT_DIR=$tmp" <<<"$root_context"
grep -Fq 'DEPLOY_ENV=dev' <<<"$root_context"
grep -Fq "SCRIPT_DIR=$tmp/deploy/prd" <<<"$deploy_context"
grep -Fq 'DEPLOY_ENV=prd' <<<"$deploy_context"

echo 'PASS: independent observability setup contract'

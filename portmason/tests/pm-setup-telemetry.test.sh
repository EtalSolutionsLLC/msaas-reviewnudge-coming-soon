#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
ENTRY="$ROOT/pm-setup-telemetry"
HELPERS="$ROOT/pm-helpers-telemetry"

bash -n "$ENTRY" "$HELPERS" "$ROOT/pm-telemetry-status"
[[ "$(sed -n '5p' "$ENTRY")" == '. "${PORTMASON_SHARE}/pm-helpers" "$@"' ]]
grep -Fq '. "${PORTMASON_SHARE}/pm-helpers-telemetry" --minimal' "$ENTRY"

! grep -Eqi 'telemetry' "$ROOT/pm-setup"
! grep -Eqi 'telemetry' "$ROOT/pm-deploy-local"

grep -Fq '${ENV_FILE:?ENV_FILE required}.generated' "$HELPERS"
grep -Fq 'pm_telemetry_render_environment' "$ENTRY"
grep -Fq 'pm_telemetry_deploy_local_realization' "$ENTRY"
grep -Fq 'pm_telemetry_verify_local_realization' "$ENTRY"
grep -Fq 'up -d --pull missing --remove-orphans --wait' "$HELPERS"
grep -Fq 'Telemetry dashboard did not become ready within 60 seconds' "$HELPERS"
! grep -Eq '(^|[[:space:]])(stop|down)([|)])' "$ENTRY" "$HELPERS"
! grep -Eq 'RUNTIME_[A-Z_]*|DB_PROVIDER|DB_PLATFORM' "$ENTRY"
! grep -Fq 'TELEMETRY_DB_ENABLED' "$HELPERS"
! grep -Fq 'PM_TELEMETRY_STORE_ENABLED' "$HELPERS"

grep -Fq 'TELEMETRY_ENABLED' "$HELPERS"
grep -Fq 'TELEMETRY_STORE_PROVIDER_PLATFORM_CODE is required when telemetry is enabled' "$HELPERS"
grep -Fq 'TELEMETRY_DASHBOARD_ENABLED' "$HELPERS"

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
  'TELEMETRY_ENABLED=false' >"$tmp/.env"
printf '%s\n' \
  'APP_SLUG=sample' \
  'DEPLOY_ENV=prd' \
  'STACK=${APP_SLUG}-${DEPLOY_ENV}' \
  'APP_URL=https://${STACK}.example.test' \
  'TELEMETRY_ENABLED=false' >"$tmp/deploy/prd/.env"

root_context="$(cd -- "$tmp" && PORTMASON_SHARE="$ROOT" "$ENTRY" --bootstrap-context)"
deploy_context="$(cd -- "$tmp/deploy/prd" && PORTMASON_SHARE="$ROOT" "$ENTRY" --bootstrap-context)"
grep -Fq "SCRIPT_DIR=$tmp" <<<"$root_context"
grep -Fq 'DEPLOY_ENV=dev' <<<"$root_context"
grep -Fq "SCRIPT_DIR=$tmp/deploy/prd" <<<"$deploy_context"
grep -Fq 'DEPLOY_ENV=prd' <<<"$deploy_context"

echo 'PASS: independent telemetry setup contract'

#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

mkdir -p "$tmp/portmason"
cat >"$tmp/portmason/pm-helpers" <<'HELPERS'
log() { :; }
die() { printf 'ERROR: %s\n' "${1:-unknown}" >&2; return "${2:-1}"; }
get_gcp_project_number() {
    [[ "${1:?project ID required}" == "test-project" ]]
    printf '12591908479'
}
HELPERS

export PORTMASON_SHARE="$tmp/portmason"
export STACK=test-prd
export DEPLOYMENT_ID=test-project
export SECRET_PATHS=$'DB_API_KEY|gcp:test-project:neon-api-key\nPAYMENTS_SECRET_KEY|gcp:payments-secret-key'

# shellcheck disable=SC1091
. "$root/pm-helpers-gcp-secrets"

pm_gcp_secret_location_for_key project secret DB_API_KEY
[[ "$project" == "12591908479" ]]
[[ "$secret" == "neon-api-key" ]]

pm_gcp_secret_location_for_key project secret PAYMENTS_SECRET_KEY
[[ "$project" == "12591908479" ]]
[[ "$secret" == "payments-secret-key" ]]

pm_gcp_secret_resource_for_key resource PAYMENTS_SECRET_KEY
[[ "$resource" == "projects/12591908479/secrets/payments-secret-key" ]]

printf 'PASS: GCP SECRET_PATHS overrides return canonical resource paths\n'

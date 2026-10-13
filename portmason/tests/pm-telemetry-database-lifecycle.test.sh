#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

bash -n \
  "$root/pm-config-database" \
  "$root/pm-setup-observability" \
  "$root/pm-helpers-db" \
  "$root/pm-provision-postgres" \
  "$root/pm-provision-gcp" \
  "$root/pm-db-bridge-postgres-gcp" \
  "$root/pm-deploy-gcp"

grep -Fq 'OBSERVABILITY_DB_PASSWORD secret' "$root/pm-config-database"
grep -Fq 'OBSERVABILITY_DB_URL secret' "$root/pm-config-database"
grep -Fq 'OBSERVABILITY_CLOUD_SQL_CONNECTION_NAME control-plane' "$root/pm-config-database"
grep -Fq 'OBSERVABILITY_DB_PROVIDER_PLATFORM_CODE var' "$root/pm-config-database"
grep -Fq 'PM_OBSERVABILITY_DB_ADMIN_NAME="$DB_ADMIN_DATABASE"' "$root/pm-helpers-neon"
grep -Fq 'PM_DB_RT_DATABASE="${PM_OBSERVABILITY_DB_ADMIN_NAME:-postgres}"' "$root/pm-provision-observability-db-postgres"
! grep -Fq 'PM_DB_RT_DATABASE=postgres' "$root/pm-provision-observability-db-postgres"
grep -Fq 'pm_secret_resolve_value resolved_secret "$key" "${!key:-}"' "$root/pm-helpers"
grep -Fq 'pm_observability_hydrate_secret OBSERVABILITY_DB_PASSWORD' "$root/pm-provision-observability-db-postgres"

grep -Fq 'pm_db_call_optional pm_db_bridge_provision_additional' "$root/pm-helpers-db"
grep -Fq 'pm_db_call_optional pm_db_bridge_deploy_additional' "$root/pm-helpers-db"
grep -Fq 'pm_postgres_provision_contract()' "$root/pm-provision-postgres"
grep -Fq 'pm_gcp_provision_observability_database_platform()' "$root/pm-provision-gcp"
grep -Fq 'OBSERVABILITY_CLOUD_SQL_CONNECTION_NAME' "$root/pm-provision-gcp"
grep -Fq 'PM_DB_RT_CONNECTION' "$root/pm-db-bridge-postgres-gcp"
grep -Fq 'pm_db_bridge_provision_additional()' "$root/pm-db-bridge-postgres-gcp"
grep -Fq 'pm_db_bridge_deploy_additional()' "$root/pm-db-bridge-postgres-gcp"
grep -Fq 'pm_gcp_cloud_sql_connections_csv()' "$root/pm-deploy-gcp"
grep -Fq '.role != "db"' "$root/pm-helpers-db"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT INT TERM
mkdir -p "$tmp/share"
cp "$root/pm-provision-observability-db-postgres" "$tmp/share/"
cat >"$tmp/share/pm-helpers" <<'SH'
log() { :; }
pm_observability_hydrate_secret() { :; }
die() {
  printf '%s\n' "$1" >&2
  return "${2:-1}"
}
db_rt() {
  printf '%s|%s|%s|%s|%s\n' \
    "$PM_DB_RT_HOST" "$PM_DB_RT_PORT" "$PM_DB_RT_USER" \
    "$PM_DB_RT_PASSWORD" "$PM_DB_RT_DATABASE" >>"${TRACE:?}"
  cat >/dev/null
}
SH

trace="$tmp/db-rt.trace"
: >"$trace"
TRACE="$trace" \
PORTMASON_SHARE="$tmp/share" \
PM_OBSERVABILITY_DB_PROVIDER_CODE=postgres \
PM_OBSERVABILITY_DB_PLATFORM_CODE=neon \
PM_OBSERVABILITY_DB_ADMIN_HOST=admin.example \
PM_OBSERVABILITY_DB_ADMIN_PORT=6432 \
PM_OBSERVABILITY_DB_ADMIN_USER=bootstrap_owner \
PM_OBSERVABILITY_DB_ADMIN_PASSWORD=bootstrap-secret \
PM_OBSERVABILITY_DB_ADMIN_NAME=neondb \
OBSERVABILITY_DB_HOST=observability-pooler.example \
OBSERVABILITY_DB_PORT=5432 \
OBSERVABILITY_DB_NAME=reviewnudge_observability \
OBSERVABILITY_DB_USER=observabilitobservabilitobservabilitobservability_app \
OBSERVABILITY_DB_PASSWORD=app-secret \
  bash "$tmp/share/pm-provision-observability-db-postgres"

[[ "$(sed -n '1p' "$trace")" == 'observability-pooler.example|5432|observabilitobservabilitobservabilitobservability_app|app-secret|reviewnudge_observability' ]]
[[ "$(wc -l <"$trace")" -eq 1 ]]

echo 'PASS: observability database lifecycle contract'

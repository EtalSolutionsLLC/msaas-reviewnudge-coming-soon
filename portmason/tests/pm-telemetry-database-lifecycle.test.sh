#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

bash -n \
  "$root/pm-config-database" \
  "$root/pm-setup-telemetry" \
  "$root/pm-helpers-db" \
  "$root/pm-provision-postgres" \
  "$root/pm-provision-gcp" \
  "$root/pm-db-bridge-postgres-gcp" \
  "$root/pm-deploy-gcp"

grep -Fq 'TELEMETRY_DB_PASSWORD secret' "$root/pm-config-database"
grep -Fq 'TELEMETRY_DB_URL secret' "$root/pm-config-database"
grep -Fq 'TELEMETRY_CLOUD_SQL_CONNECTION_NAME control-plane' "$root/pm-config-database"
grep -Fq 'TELEMETRY_DB_PROVIDER_PLATFORM_CODE var' "$root/pm-config-database"
grep -Fq 'PM_TELEMETRY_DB_ADMIN_NAME="$DB_ADMIN_DATABASE"' "$root/pm-helpers-neon"
grep -Fq 'PM_DB_RT_DATABASE="${PM_TELEMETRY_DB_ADMIN_NAME:-postgres}"' "$root/pm-provision-telemetry-db-postgres"
! grep -Fq 'PM_DB_RT_DATABASE=postgres' "$root/pm-provision-telemetry-db-postgres"
grep -Fq 'pm_secret_resolve_value resolved_secret "$key" "${!key:-}"' "$root/pm-helpers"
grep -Fq 'pm_telemetry_hydrate_secret TELEMETRY_DB_PASSWORD' "$root/pm-provision-telemetry-db-postgres"

grep -Fq 'pm_db_call_optional pm_db_bridge_provision_additional' "$root/pm-helpers-db"
grep -Fq 'pm_db_call_optional pm_db_bridge_deploy_additional' "$root/pm-helpers-db"
grep -Fq 'pm_postgres_provision_contract()' "$root/pm-provision-postgres"
grep -Fq 'pm_gcp_provision_telemetry_database_platform()' "$root/pm-provision-gcp"
grep -Fq 'TELEMETRY_CLOUD_SQL_CONNECTION_NAME' "$root/pm-provision-gcp"
grep -Fq 'PM_DB_RT_CONNECTION' "$root/pm-db-bridge-postgres-gcp"
grep -Fq 'pm_db_bridge_provision_additional()' "$root/pm-db-bridge-postgres-gcp"
grep -Fq 'pm_db_bridge_deploy_additional()' "$root/pm-db-bridge-postgres-gcp"
grep -Fq 'pm_gcp_cloud_sql_connections_csv()' "$root/pm-deploy-gcp"
grep -Fq '.role != "db"' "$root/pm-helpers-db"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT INT TERM
mkdir -p "$tmp/share"
cp "$root/pm-provision-telemetry-db-postgres" "$tmp/share/"
cat >"$tmp/share/pm-helpers" <<'SH'
log() { :; }
pm_telemetry_hydrate_secret() { :; }
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
PM_TELEMETRY_DB_PROVIDER_CODE=postgres \
PM_TELEMETRY_DB_PLATFORM_CODE=neon \
PM_TELEMETRY_DB_ADMIN_HOST=admin.example \
PM_TELEMETRY_DB_ADMIN_PORT=6432 \
PM_TELEMETRY_DB_ADMIN_USER=bootstrap_owner \
PM_TELEMETRY_DB_ADMIN_PASSWORD=bootstrap-secret \
PM_TELEMETRY_DB_ADMIN_NAME=neondb \
TELEMETRY_DB_HOST=telemetry-pooler.example \
TELEMETRY_DB_PORT=5432 \
TELEMETRY_DB_NAME=reviewnudge_telemetry \
TELEMETRY_DB_USER=telemetry_app \
TELEMETRY_DB_PASSWORD=app-secret \
  bash "$tmp/share/pm-provision-telemetry-db-postgres"

[[ "$(sed -n '1p' "$trace")" == 'telemetry-pooler.example|5432|telemetry_app|app-secret|reviewnudge_telemetry' ]]
[[ "$(wc -l <"$trace")" -eq 1 ]]

echo 'PASS: telemetry database lifecycle contract'

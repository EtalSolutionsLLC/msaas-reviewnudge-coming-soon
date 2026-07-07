#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
helpers="$source_dir/pm-helpers"
setup="$source_dir/pm-setup"

! grep -Fq 'load_database_provider_hook' "$helpers"
! grep -Fq 'load_database_provider_hook' "$setup"

db_bootstrap_line="$(grep -n 'pm_db_bootstrap_helpers' "$helpers" | tail -1 | cut -d: -f1)"
bridge_line="$(grep -n '^[[:space:]]*load_bridge_runtime_adapter' "$helpers" | tail -1 | cut -d: -f1)"
adapter_line="$(grep -n '^[[:space:]]*load_adapter_helper' "$helpers" | tail -1 | cut -d: -f1)"
runtime_line="$(grep -n '^[[:space:]]*load_runtime_helper' "$helpers" | tail -1 | cut -d: -f1)"

(( db_bootstrap_line < bridge_line ))
(( db_bootstrap_line < adapter_line ))
(( db_bootstrap_line < runtime_line ))

preflight_line="$(grep -n '^[[:space:]]*if ! pm_db_preflight' "$setup" | cut -d: -f1)"
runtime_provision_line="$(grep -n '^[[:space:]]*pm_setup_run_runtime_platform_provision' "$setup" | tail -1 | cut -d: -f1)"
db_provision_line="$(grep -n '^[[:space:]]*pm_db_run_provision' "$setup" | tail -1 | cut -d: -f1)"
db_deploy_line="$(grep -n '^[[:space:]]*pm_db_run_deploy' "$setup" | tail -1 | cut -d: -f1)"
app_line="$(grep -n '^[[:space:]]*pm_setup_run_application_phase' "$setup" | tail -1 | cut -d: -f1)"

(( preflight_line < runtime_provision_line ))
(( runtime_provision_line < db_provision_line ))
(( db_provision_line < db_deploy_line ))
(( db_deploy_line < app_line ))

for file in \
    pm-helpers-db pm-helpers-postgres pm-helpers-gcp-secrets \
    pm-db-bridge-postgres-local pm-db-bridge-postgres-gcp \
    pm-provision-postgres pm-deploy-postgres \
    pm-provision-local pm-deploy-local pm-provision-gcp pm-deploy-gcp pm-setup
 do
    bash -n "$source_dir/$file"
done

printf 'Portmason database bootstrap and lifecycle-order tests passed.\n'

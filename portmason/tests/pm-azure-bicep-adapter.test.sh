#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

bash -n "$source_dir/pm-helpers-azure"
bash -n "$source_dir/pm-provision-azure"
bash -n "$source_dir/pm-deploy-azure"

grep -Fq 'pm_provision_runtime_platform()' "$source_dir/pm-provision-azure"
grep -Fq 'pm_deploy_runtime_platform()' "$source_dir/pm-deploy-azure"
grep -Fq 'pm_setup_run_runtime_platform_provision' "$source_dir/pm-setup"
grep -Fq 'pm_setup_run_runtime_platform_deploy' "$source_dir/pm-setup"

grep -Fq 'local deployment_principal_id deployment_principal_type queues_json' \
    "$source_dir/pm-provision-azure"
grep -Fq 'pm_azure_current_principal deployment_principal_id deployment_principal_type' \
    "$source_dir/pm-provision-azure"
! grep -Fq 'pm_azure_current_principal principal_id principal_type' \
    "$source_dir/pm-provision-azure"

grep -Fq 'deployment sub create' "$source_dir/pm-provision-azure"
grep -Fq 'deployment group create' "$source_dir/pm-deploy-azure"
grep -Fq 'deployment sub validate' "$source_dir/pm-provision-azure"
grep -Fq 'deployment group validate' "$source_dir/pm-deploy-azure"
grep -Fq 'deployment sub what-if' "$source_dir/pm-provision-azure"
grep -Fq 'deployment group what-if' "$source_dir/pm-deploy-azure"
grep -Fq 'env_init_set ALTERNATE_APP_URL "$app_url"' "$source_dir/pm-deploy-azure"
grep -Fq 'alternate_app_url=${ALTERNATE_APP_URL:-<not-applicable>}' "$source_dir/pm-deploy-azure"

! grep -Fq 'acr create' "$source_dir/pm-provision-azure"
! grep -Fq 'keyvault create' "$source_dir/pm-provision-azure"
! grep -Fq 'identity create' "$source_dir/pm-provision-azure"
! grep -Fq 'containerapp create' "$source_dir/pm-deploy-azure"
! grep -Fq 'containerapp update' "$source_dir/pm-deploy-azure"

platform="$source_dir/share/azure/platform.bicep"
platform_resources="$source_dir/share/azure/modules/platform-resources.bicep"
application="$source_dir/share/azure/application.bicep"

[[ -r "$platform" ]]
[[ -r "$platform_resources" ]]
[[ -r "$application" ]]

grep -Fq "targetScope = 'subscription'" "$platform"
grep -Fq "Microsoft.Resources/resourceGroups" "$platform"
grep -Fq "Microsoft.ContainerRegistry/registries" "$platform_resources"
grep -Fq "Microsoft.KeyVault/vaults" "$platform_resources"
grep -Fq "Microsoft.ManagedIdentity/userAssignedIdentities" "$platform_resources"
grep -Fq "Microsoft.App/managedEnvironments" "$platform_resources"
grep -Fq "Microsoft.Authorization/roleAssignments" "$platform_resources"
grep -Fq '7f951dda-4ed3-4680-a7ca-43fe172d538d' "$platform_resources"
grep -Fq '4633458b-17de-408a-b874-0445c86b69e6' "$platform_resources"
grep -Fq 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7' "$platform_resources"
grep -Fq "Microsoft.App/containerApps" "$application"
grep -Fq "Microsoft.App/jobs" "$application"

! grep -RInE 'DB_PASSWORD|CHECKOUT_TOKEN_KEY|STRIPE_SECRET_KEY' \
    "$source_dir/share/azure" >/dev/null

if command -v az >/dev/null 2>&1; then
    az bicep build --file "$platform" --stdout >/dev/null
    az bicep build --file "$application" --stdout >/dev/null
fi

printf 'Portmason Azure Bicep adapter contract tests passed.\n'

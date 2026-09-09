#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

log() { :; }
die() { printf '%s\n' "$*" >&2; return "${2:-1}"; }
have() { command -v "$1" >/dev/null 2>&1; }
env_init_set() { printf -v "$1" '%s' "${2-}"; export "$1"; }
export -f log die have env_init_set

. "$source_dir/pm-helpers-azure"

STACK='ReviewNudge PRD'
BUILD_NUMBER=123
AZURE_DEPLOYMENT_PRINCIPAL_ID='00000000-0000-0000-0000-000000000001'
AZURE_DEPLOYMENT_PRINCIPAL_TYPE='User'

principal_object_id=''
principal_kind=''
pm_azure_current_principal principal_object_id principal_kind
[[ "$principal_object_id" == "$AZURE_DEPLOYMENT_PRINCIPAL_ID" ]]
[[ "$principal_kind" == "$AZURE_DEPLOYMENT_PRINCIPAL_TYPE" ]]

deployment_name=''
pm_azure_slug deployment_name "${STACK}-platform-${BUILD_NUMBER}"
[[ "$deployment_name" == 'reviewnudge-prd-platform-123' ]]

printf 'Portmason Azure output collision regression tests passed.\n'

#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM
mkdir -p "$temp_dir/project"
touch "$temp_dir/project/.env"

export PORTMASON_SHARE="$source_dir"
export SCRIPT_DIR="$temp_dir/project"
export ENV_FILE="$temp_dir/project/.env"
export RUNTIME_ADAPTER_CODE=node-azure
export DB_PROVIDER_PLATFORM_CODE=postgres-neon
export DEPLOY_ENV=prd
export STACK=test-prd
export PROJECT_ID=test-azure-project
export DEPLOYMENT_ID=test-azure-project
export GITHUB_ACTIONS=true
export TEST_GITHUB_ACTIONS_SECRET='mock-github-secret-value'
export SECRET_PATHS='TEST_SECRET|github:TEST_GITHUB_ACTIONS_SECRET'

log() { :; }
die() { printf 'ERROR: %s\n' "${1:-unknown}" >&2; return "${2:-1}"; }
export -f log die

cd "$temp_dir/project"

# shellcheck disable=SC1091
. "$source_dir/pm-helpers"

if declare -F pm-publish-finalize-static >/dev/null 2>&1; then
    printf 'FAIL: static finalizer loaded for non-static runtime\n' >&2
    exit 1
fi

value="$(get_secret 'github:TEST_GITHUB_ACTIONS_SECRET')"
[[ "$value" == 'mock-github-secret-value' ]]

path="$(get_secret_path_by_ref TEST_SECRET)"
[[ "$path" == 'github:TEST_GITHUB_ACTIONS_SECRET' ]]

name="$(get_secret_name_by_ref TEST_SECRET)"
[[ "$name" == 'TEST_GITHUB_ACTIONS_SECRET' ]]

unset TEST_GITHUB_ACTIONS_SECRET
if (get_secret 'github:TEST_GITHUB_ACTIONS_SECRET' >/dev/null 2>&1); then
    printf 'FAIL: missing GitHub Actions secret unexpectedly resolved\n' >&2
    exit 1
fi

printf 'PASS: GitHub Actions secret provider resolves injected values by github: path\n'

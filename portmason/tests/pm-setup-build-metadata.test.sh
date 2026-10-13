#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
setup="$root/pm-setup"

bash -n "$setup"
grep -Fq 'pm_setup_allocate_build_number "$@"' "$setup"
grep -Fq 'build allocate --allow-local' "$setup"
grep -Fq 'PM_VERSION_ROOT="$PROJECT_ROOT" "$version_command" build materialize --site-dir "$SITE_ROOT"' "$setup"
grep -Fq 'rolled back allocated build after failed setup' "$setup"
grep -Fq 'build materialize --site-dir "$SITE_ROOT"' "$setup"
grep -Fq 'SITE_ROOT is required to materialize build metadata' "$setup"

tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/node/public" "$tmp/static/www"

env_init_set() { printf -v "$1" '%s' "$2"; export "$1"; }
log() { :; }

PROJECT_ROOT="$tmp/node"
SITE_DIR="$tmp/node"
SITE_ROOT="$SITE_DIR"
MGT_SCRIPTS="$tmp/node/mgt-scripts"
source "$root/pm-setup-node"
[[ "$SITE_ROOT" == "$tmp/node/public" ]]

mkdir -p "$tmp/node/deploy/prd/public" "$tmp/node/deploy/prd/mgt-scripts"
SITE_ROOT="$tmp/node/public"
MGT_SCRIPTS="$tmp/node/deploy/prd/mgt-scripts"
source "$root/pm-setup-node"
[[ "$SITE_ROOT" == "$tmp/node/deploy/prd/public" ]]

PROJECT_ROOT="$tmp/static"
SITE_DIR="$tmp/static/www"
SITE_ROOT="$SITE_DIR"
source "$root/pm-setup-static"
[[ "$SITE_ROOT" == "$tmp/static/www" ]]

printf '138\n' > "$tmp/node/BUILD_NUMBER"
printf '{"version":"1.0.0-rc.3"}\n' > "$tmp/node/package.json"
PM_VERSION_ROOT="$tmp/node" "$root/pm-version" build materialize --site-dir "$tmp/node/public" >/dev/null
[[ "$(jq -r '.buildNumber' "$tmp/node/public/build-info.json")" == "138" ]]
[[ "$(jq -r '.releaseVersion' "$tmp/node/public/build-info.json")" == "1.0.0-rc.3" ]]

allocation_line="$(grep -n 'pm_setup_allocate_build_number "$@"' "$setup" | tail -n1 | cut -d: -f1)"
metadata_line="$(grep -n 'pm_setup_run_application_phase "$@"' "$setup" | tail -n1 | cut -d: -f1)"
deploy_line="$(grep -n 'pm_setup_log_completion' "$setup" | tail -n1 | cut -d: -f1)"
((allocation_line < metadata_line))
((metadata_line < deploy_line))

echo "PASS: pm-setup materializes build metadata before runtime deployment"

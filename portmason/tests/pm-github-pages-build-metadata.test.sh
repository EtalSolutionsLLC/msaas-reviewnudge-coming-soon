#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT INT TERM

mkdir -p "$fixture/www"
git -C "$fixture" init -q
printf '1.0.0\n' > "$fixture/RELEASE_VERSION"
printf '165\n' > "$fixture/BUILD_NUMBER"
printf '<!doctype html><title>Fixture</title>\n' > "$fixture/www/index.html"
cat > "$fixture/.env" <<'ENV'
APP_SLUG=github-pages-fixture
DEPLOY_ENV=prd
RUNTIME_ADAPTER_CODE=static-github
ENV_ROOT=${REPO_ROOT}
SITE_ROOT=${ENV_ROOT}/www
SITE_DIR=${SITE_ROOT}
LOG_DIR=${REPO_ROOT}/logs
ENV

log() { :; }
die() {
    printf '%s\n' "$1" >&2
    return "${2:-1}"
}
PROJECT_ROOT="$fixture"
SITE_DIR="$fixture/www"
GITHUB_PAGES_BUILD_DIR="$fixture/www"
GITHUB_PAGES_CONFIG_JSON="$fixture/www/config.public.json"
PORTMASON_SHARE="$root"
PM_OFFICIAL_BUILD=true
PM_SOURCE_COMMIT=0123456789abcdef0123456789abcdef01234567
PM_SOURCE_DIRTY=false
PM_DEPLOY_ENV=prd
PM_DEPLOYMENT_ID=github-12345-1
ENV_FILE="$fixture/.env"
export PROJECT_ROOT SITE_DIR GITHUB_PAGES_BUILD_DIR GITHUB_PAGES_CONFIG_JSON
export PORTMASON_SHARE PM_OFFICIAL_BUILD PM_SOURCE_COMMIT PM_SOURCE_DIRTY
export PM_DEPLOY_ENV PM_DEPLOYMENT_ID ENV_FILE

source "$root/pm-helpers-github"
pm_github_write_browser_config() {
    printf '{"siteUrl":"https://example.test"}\n' > "$1"
}
github_pages_prepare

for required_file in build-info.json deploy-info.json artifact-manifest.json; do
    [[ -s "$fixture/www/$required_file" ]]
done

[[ -s "$fixture/www/config.public.json" ]]
[[ -e "$fixture/www/.nojekyll" ]]
(
    cd -- "$fixture"
    PM_VERSION_ROOT="$fixture" \
        "$root/pm-version" deployment verify --site-dir "$fixture/www" >/dev/null
)
[[ "$(jq -r '.deploymentId' "$fixture/www/deploy-info.json")" == github-12345-1 ]]

echo "PASS: GitHub Pages prepares and verifies its exact published artifact"

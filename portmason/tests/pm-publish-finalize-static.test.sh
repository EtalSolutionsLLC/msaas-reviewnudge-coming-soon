#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM
mkdir -p "$temp_dir/bin" "$temp_dir/project"
touch "$temp_dir/project/.env"

cat >"$temp_dir/bin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

url=""
authorization=""
request_body=""

while (($#)); do
    case "$1" in
        --header)
            shift
            case "$1" in
                Authorization:*) authorization="$1" ;;
            esac
            ;;
        --data)
            shift
            request_body="$1"
            ;;
        https://*)
            url="$1"
            ;;
    esac
    shift
done

[[ "$authorization" == 'Authorization: Bearer mock-cloudflare-token' ]]
[[ "$url" == 'https://api.cloudflare.com/client/v4/zones/mock-zone-id/purge_cache' ]]
jq --exit-status '.hosts == ["david.example.test"]' >/dev/null <<<"$request_body"

printf '%s\n' "$url" >"${MOCK_CURL_TRACE:?}"
printf '%s\n' "$request_body" >>"${MOCK_CURL_TRACE:?}"
printf '%s\n' "${MOCK_CLOUDFLARE_RESPONSE:-{\"success\":true,\"errors\":[]}}"
SH
chmod +x "$temp_dir/bin/curl"

export PATH="$temp_dir/bin:$PATH"
export MOCK_CURL_TRACE="$temp_dir/curl.trace"
export PORTMASON_SHARE="$source_dir"
export SCRIPT_DIR="$temp_dir/project"
export ENV_FILE="$temp_dir/project/.env"
export RUNTIME_ADAPTER_CODE=static-github
export DB_PROVIDER_PLATFORM_CODE=none-none
export DEPLOY_ENV=prd
export STACK=test-prd
export PROJECT_ID=test-project
export DEPLOYMENT_ID=test-deployment
export GITHUB_ACTIONS=true
export APP_URL='https://david.example.test/'
export CLOUDFLARE_ZONE_ID='mock-zone-id'
export CLOUDFLARE_API_TOKEN='mock-cloudflare-token'
export SECRET_PATHS='CLOUDFLARE_API_TOKEN|github:CLOUDFLARE_API_TOKEN'

log() { :; }
die() { printf 'ERROR: %s\n' "${1:-unknown}" >&2; return "${2:-1}"; }
export -f log die

cd "$temp_dir/project"

# shellcheck disable=SC1091
. "$source_dir/pm-helpers"

declare -F pm-publish-finalize-static >/dev/null
pm-publish-finalize-static

grep -Fxq 'https://api.cloudflare.com/client/v4/zones/mock-zone-id/purge_cache' "$MOCK_CURL_TRACE"
grep -Fxq '{"hosts":["david.example.test"]}' "$MOCK_CURL_TRACE"

export MOCK_CLOUDFLARE_RESPONSE='{"success":false,"errors":[{"code":1000,"message":"mock rejection"}]}'
if (pm-publish-finalize-static >/dev/null 2>&1); then
    printf 'FAIL: rejected Cloudflare purge unexpectedly succeeded\n' >&2
    exit 1
fi

printf 'PASS: static publication finalizer purges the published Cloudflare hostname\n'

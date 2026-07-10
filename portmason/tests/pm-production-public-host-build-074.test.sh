#!/usr/bin/env bash
set -euo pipefail

source_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_root="$(mktemp -d)"
trap 'rm -rf -- "$temp_root"' EXIT

make_project() {
    local name="$1"
    local deploy_env="$2"
    local host="$3"
    local project="$temp_root/$name"

    mkdir -p "$project/site"
    git -C "$project" init -q
    cat > "$project/.env" <<ENV
APP_SLUG=reviewnudge
DEPLOY_ENV=$deploy_env
RUNTIME_ADAPTER_CODE=node-local
STACK=reviewnudge${deploy_env:+-$deploy_env}
LOCAL_DOMAIN=etal.solutions
APP_HOST=$host
APP_BASE_URL=https://$host
APP_URL=https://$host
URI_SCHEME=https:
WP_SITE_URL=https://$host
PROJECT_ID=reviewnudge-test-074
DEPLOYMENT_ID=reviewnudge-test-074
ENV

    printf '%s' "$project"
}

prd_project="$(make_project prd prd reviewnudge-prd.etal.solutions)"
(
    cd "$prd_project"
    export PORTMASON_SHARE="$source_root"
    export ENV_FILE="$prd_project/.env"
    export SITE_DIR="$prd_project/site"
    export MINIMAL=1
    # shellcheck source=/dev/null
    . "$source_root/pm-helpers"

    [[ "$STACK" == "reviewnudge-prd" ]]
    [[ "$APP_HOST" == "reviewnudge.etal.solutions" ]]
    [[ "$APP_URL" == "https://reviewnudge.etal.solutions" ]]
    [[ "$APP_BASE_URL" == "https://reviewnudge.etal.solutions" ]]
    [[ "$WP_SITE_URL" == "https://reviewnudge.etal.solutions" ]]

    "$source_root/pm-generate-config"

    grep -Fxq 'STACK=reviewnudge-prd' .env.generated
    grep -Fxq 'APP_HOST=reviewnudge.etal.solutions' .env.generated
    grep -Fxq 'APP_URL=https://reviewnudge.etal.solutions' .env.generated
    grep -Fxq 'APP_BASE_URL=https://reviewnudge.etal.solutions' .env.generated
    grep -Fxq 'WP_SITE_URL=https://reviewnudge.etal.solutions' .env.generated
    ! grep -Fq 'reviewnudge-prd.etal.solutions' .env.generated

    python3 - <<'PY'
import json
from pathlib import Path
payload = json.loads(Path('site/config.generated.json').read_text())
assert payload['STACK'] == 'reviewnudge-prd'
assert payload['APP_HOST'] == 'reviewnudge.etal.solutions'
assert payload['APP_URL'] == 'https://reviewnudge.etal.solutions'
assert payload['APP_BASE_URL'] == 'https://reviewnudge.etal.solutions'
assert payload['WP_SITE_URL'] == 'https://reviewnudge.etal.solutions'
PY
)

qas_project="$(make_project qas qas reviewnudge-qas.etal.solutions)"
(
    cd "$qas_project"
    export PORTMASON_SHARE="$source_root"
    export ENV_FILE="$qas_project/.env"
    export SITE_DIR="$qas_project/site"
    export MINIMAL=1
    # shellcheck source=/dev/null
    . "$source_root/pm-helpers"

    [[ "$STACK" == "reviewnudge-qas" ]]
    [[ "$APP_HOST" == "reviewnudge-qas.etal.solutions" ]]
    [[ "$APP_URL" == "https://reviewnudge-qas.etal.solutions" ]]
)

printf 'PASS: production public host omits DEPLOY_ENV while STACK remains namespaced\n'

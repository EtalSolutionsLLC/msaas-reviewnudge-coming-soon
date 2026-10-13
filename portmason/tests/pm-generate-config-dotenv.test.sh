#!/usr/bin/env bash
set -euo pipefail

source_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_root="$(mktemp -d)"
trap 'rm -rf -- "$temp_root"' EXIT

project="$temp_root/project"
mkdir -p "$project/site"
git -C "$project" init -q

cat > "$project/.env" <<'ENV'
APP_SLUG=reviewnudge
DEPLOY_ENV=prd
RUNTIME_ADAPTER_CODE=bash-env
STACK=reviewnudge-prd
APP_HOST=reviewnudge.example.com
APP_URL=https://reviewnudge.example.com
SITE_URL=https://reviewnudge.example.com
SUPPORT_CHANNEL_OPERATING_HOURS_DAYS=0,1,2,3,4,5
BULKEMAILER_FROM='ReviewNudge <reviews@send.etal.solutions>'
BULKEMAILER_SUBJECT='A quick review request'
PROJECT_ID=reviewnudge-test-dotenv
DEPLOYMENT_ID=reviewnudge-test-dotenv
ENV

(
    cd "$project"

    export PORTMASON_SHARE="$source_root"
    export ENV_FILE="$project/.env"
    export SITE_DIR="$project/site"

    # shellcheck source=/dev/null
    . "$source_root/pm-helpers"

    "$source_root/pm-generate-config"

    grep -Fxq \
        'SUPPORT_CHANNEL_OPERATING_HOURS_DAYS=0,1,2,3,4,5' \
        .env.generated

    grep -Fxq \
        "BULKEMAILER_FROM='ReviewNudge <reviews@send.etal.solutions>'" \
        .env.generated

    grep -Fxq \
        "BULKEMAILER_SUBJECT='A quick review request'" \
        .env.generated

    if grep -Fq '\,' .env.generated; then
        printf 'FAIL: generated dotenv contains Bash %%q comma escaping\n' >&2
        grep -nF '\,' .env.generated >&2 || true
        exit 1
    fi

    set -a
    # shellcheck disable=SC1091
    . ./.env.generated
    set +a

    [[ "$SUPPORT_CHANNEL_OPERATING_HOURS_DAYS" == '0,1,2,3,4,5' ]]
    [[ "$BULKEMAILER_FROM" == 'ReviewNudge <reviews@send.etal.solutions>' ]]
    [[ "$BULKEMAILER_SUBJECT" == 'A quick review request' ]]
)

printf 'PASS: pm-generate-config emits Compose/Bash-compatible dotenv values\n'

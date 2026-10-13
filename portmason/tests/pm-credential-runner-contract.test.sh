#!/usr/bin/env bash
set -euo pipefail

PORTMASON_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM

env_file="${temp_dir}/.env"
cat >"$env_file" <<'ENV'
DEPLOY_ENV=dev
CLOUDFLARE_ACCOUNT_ID=account-123
CLOUDFLARE_API_TOKEN=token-123
TURNSTILE_WIDGET_NAME=reviewnudge-dev
TURNSTILE_SITE_KEY=site-123
TURNSTILE_SECRET_KEY=secret-123
TURNSTILE_VERIFY_URL=https://challenges.cloudflare.com/turnstile/v0/siteverify
TURNSTILE_TIMEOUT_MS=10000
ENV

inventory="$("${PORTMASON_DIR}/pm-control-plane" secrets inventory --env-file "$env_file")"
jq -e '.secrets[0].name == "TURNSTILE_SECRET_KEY"' >/dev/null <<<"$inventory"
jq -e '.secrets[0].provider == "cloudflare-turnstile"' >/dev/null <<<"$inventory"
jq -e '.secrets[0].api_token_present == true' >/dev/null <<<"$inventory"
if grep -Fq 'token-123' <<<"$inventory" || grep -Fq 'secret-123' <<<"$inventory"; then
    printf 'FAIL: inventory leaked a credential value\n' >&2
    exit 1
fi

plan="$("${PORTMASON_DIR}/pm-control-plane" secrets rotate --secret TURNSTILE_SECRET_KEY --env-file "$env_file" --plan)"
jq -e '.apply == false' >/dev/null <<<"$plan"
jq -e '.will_not_revoke_old_automatically == true' >/dev/null <<<"$plan"
if grep -Fq 'token-123' <<<"$plan" || grep -Fq 'secret-123' <<<"$plan"; then
    printf 'FAIL: plan leaked a credential value\n' >&2
    exit 1
fi

printf 'PASS: credential runner inventory and plan avoid secret leakage\n'

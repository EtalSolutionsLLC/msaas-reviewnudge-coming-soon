#!/usr/bin/env bash
set -euo pipefail

PORTMASON_SHARE="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &&
    pwd -P
)"
export PORTMASON_SHARE

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "${tmp}/.env" <<'ENV'
DEPLOY_ENV=dev
RUNTIME_ADAPTER_CODE=node-local
DB_PROVIDER_PLATFORM_CODE=postgres-local
DB_PROVIDER_CODE=local
DB_PLATFORM_CODE=postgres
ENV

output="$(
    cd "$tmp"
    "${PORTMASON_SHARE}/pm-lint" \
        --root "$tmp" \
        --rule PM006 \
        --format text \
        .env 2>&1 || true
)"

grep -Fq \
    "DB_PROVIDER_CODE configured='local'; DB_PROVIDER_PLATFORM_CODE='postgres-local' derives provider='postgres' and platform='local'" \
    <<<"$output"

grep -Fq \
    "DB_PLATFORM_CODE configured='postgres'; DB_PROVIDER_PLATFORM_CODE='postgres-local' derives provider='postgres' and platform='local'" \
    <<<"$output"

bash -n "${PORTMASON_SHARE}/pm-helpers-config"
bash -n "${PORTMASON_SHARE}/lint/rules/pm-lint-rule-pm006-selector-authority"

printf 'PASS: database selector diagnostics\n'

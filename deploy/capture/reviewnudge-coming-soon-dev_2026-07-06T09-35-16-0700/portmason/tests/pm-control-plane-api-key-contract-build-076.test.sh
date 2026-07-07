#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM
mkdir -p "$temp_dir/project"
TEST_LOG="$temp_dir/test.log"

log() { printf '%s\n' "$*" >>"$TEST_LOG"; }
die() { log ERROR "$*"; return "${2:-1}"; }
have() { return 0; }
env_init_set() { printf -v "$1" '%s' "${2-}"; export "$1"; }
export -f log die have env_init_set

export PORTMASON_SHARE="$source_dir"
export SCRIPT_DIR="$temp_dir/project"
export ENV_FILE="$temp_dir/project/.env"
export SECRET_PATHS=
export PM_ADDITIONAL_SECRET_KEYS=
export PM_REQUIRED_SECRET_KEYS=
export DB_PLATFORM=neon

# shellcheck source=/dev/null
. "$source_dir/pm-helpers-db"
# shellcheck source=/dev/null
. "$source_dir/pm-helpers-neon"

for key in \
    DB_API_KEY \
    RUNTIME_API_KEY \
    DNS_API_KEY \
    STORAGE_API_KEY \
    EMAIL_API_KEY \
    BILLING_API_KEY
do
    pm_secret_key_is_canonical "$key"
done

! pm_secret_key_is_canonical NEON_API_KEY
pm_secret_key_is_deprecated_alias NEON_API_KEY
pm_secret_key_is_registered NEON_API_KEY

for role in db web app jobs worker cache; do
    ! pm_service_secret_keys "$role" | grep -Eq \
        '^(DB_API_KEY|RUNTIME_API_KEY|DNS_API_KEY|STORAGE_API_KEY|EMAIL_API_KEY|BILLING_API_KEY|NEON_API_KEY)$'
done

cat >"${ENV_FILE}.generated" <<'ENV'
DB_API_KEY=canonical-db-control-secret
RUNTIME_API_KEY=canonical-runtime-control-secret
DNS_API_KEY=canonical-dns-control-secret
STORAGE_API_KEY=canonical-storage-control-secret
EMAIL_API_KEY=canonical-email-control-secret
BILLING_API_KEY=canonical-billing-control-secret
ENV
pm_preflight_reset
pm_validate_secret_registry
(( ${#PM_PREFLIGHT_ERRORS[@]} == 0 ))

# Canonical Neon configuration passes without warnings.
unset NEON_API_KEY
DB_API_KEY=canonical-neon-key
export DB_API_KEY
pm_preflight_reset
pm_validate_deprecated_secret_aliases
pm_db_platform_preflight
(( ${#PM_PREFLIGHT_ERRORS[@]} == 0 ))
(( ${#PM_PREFLIGHT_WARNINGS[@]} == 0 ))

# The legacy provider-specific name is accepted for one transition cycle,
# warned, and mapped to the canonical name only in memory.
unset DB_API_KEY
NEON_API_KEY=legacy-neon-key
export NEON_API_KEY
pm_preflight_reset
pm_validate_deprecated_secret_aliases
pm_db_platform_preflight
(( ${#PM_PREFLIGHT_ERRORS[@]} == 0 ))
(( ${#PM_PREFLIGHT_WARNINGS[@]} == 1 ))
grep -Fq 'NEON_API_KEY' <<<"${PM_PREFLIGHT_WARNINGS[0]}"
grep -Fq 'DB_API_KEY' <<<"${PM_PREFLIGHT_WARNINGS[0]}"
pm_neon_adopt_legacy_api_key
[[ "$DB_API_KEY" == legacy-neon-key ]]
[[ -z "${NEON_API_KEY:-}" ]]

# Duplicate canonical and legacy settings are rejected before any action.
DB_API_KEY=canonical-neon-key
NEON_API_KEY=legacy-neon-key
export DB_API_KEY NEON_API_KEY
pm_preflight_reset
pm_validate_deprecated_secret_aliases
(( ${#PM_PREFLIGHT_ERRORS[@]} == 1 ))
grep -Fq 'duplicates canonical DB_API_KEY' <<<"${PM_PREFLIGHT_ERRORS[0]}"

# Missing credentials report the canonical name, never the provider alias.
unset DB_API_KEY NEON_API_KEY
pm_preflight_reset
pm_validate_deprecated_secret_aliases
pm_db_platform_preflight
(( ${#PM_PREFLIGHT_ERRORS[@]} == 1 ))
grep -Fq 'database.platform.neon|DB_API_KEY|' <<<"${PM_PREFLIGHT_ERRORS[0]}"

printf 'PASS: canonical control-plane API-key contracts and Neon DB_API_KEY mapping\n'

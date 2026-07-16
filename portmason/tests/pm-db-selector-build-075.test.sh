#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

log() { :; }
die() { printf '%s\n' "$1" >&2; return "${2:-1}"; }
env_init_set() { printf -v "$1" '%s' "${2-}"; export "$1"; }
export -f log die env_init_set

# shellcheck source=/dev/null
. "$source_dir/pm-helpers-db"

unset DB_PROVIDER_CODE DB_PLATFORM_CODE DATABASE_URL DB_HOST DB_NAME DB_USER
DB_PROVIDER_PLATFORM_CODE=postgres-neon
pm_db_refresh_selectors
[[ "$DB_PROVIDER_CODE" == postgres ]]
[[ "$DB_PLATFORM_CODE" == neon ]]

DB_PROVIDER_PLATFORM_CODE=postgres-neon
DB_PROVIDER_CODE=mysql
DB_PLATFORM_CODE=neon
if pm_db_refresh_selectors 2>/dev/null; then
    printf 'Expected conflicting DB_PROVIDER_CODE to fail.\n' >&2
    exit 1
fi

unset DB_PROVIDER_PLATFORM_CODE
DB_PROVIDER_CODE=postgres
DB_PLATFORM_CODE=local
if pm_db_refresh_selectors; then
    printf 'Expected legacy selectors without DB_PROVIDER_PLATFORM_CODE to fail.\n' >&2
    exit 1
fi

printf 'PASS: DB_PROVIDER_PLATFORM_CODE is the sole database selector\n'

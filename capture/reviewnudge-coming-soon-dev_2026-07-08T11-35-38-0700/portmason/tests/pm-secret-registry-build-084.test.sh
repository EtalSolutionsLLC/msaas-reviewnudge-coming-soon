#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PORTMASON_DIR="$(cd -- "${TEST_DIR}/.." && pwd)"

log() { :; }
die() {
    printf 'ERROR: %s\n' "${1:-unknown error}" >&2
    return "${2:-1}"
}

# shellcheck disable=SC1091
. "${PORTMASON_DIR}/pm-secret-registry"

assert_contains() {
    local haystack="${1-}"
    local needle="${2:?needle required}"
    grep -Fxq "$needle" <<<"$haystack" || {
        printf 'FAIL: expected value not found: %s\n' "$needle" >&2
        exit 1
    }
}

assert_not_contains() {
    local haystack="${1-}"
    local needle="${2:?needle required}"
    if grep -Fxq "$needle" <<<"$haystack"; then
        printf 'FAIL: unexpected value found: %s\n' "$needle" >&2
        exit 1
    fi
}

support_keys="$(pm_service_secret_keys support-bot)"
assert_contains "$support_keys" SUPPORT_CHANNEL_BOT_TOKEN
assert_contains "$support_keys" SUPPORT_CHANNEL_SOCKET_TOKEN
assert_contains "$support_keys" SUPPORT_CHANNEL_CLIENT_SECRET
assert_contains "$support_keys" SUPPORT_CHANNEL_SIGNING_SECRET
assert_not_contains "$support_keys" DB_API_KEY
assert_not_contains "$support_keys" DB_PASSWORD

web_keys="$(pm_service_secret_keys web)"
assert_contains "$web_keys" DB_PASSWORD
assert_contains "$web_keys" APP_SECRET
assert_not_contains "$web_keys" SUPPORT_CHANNEL_BOT_TOKEN
assert_not_contains "$web_keys" DB_API_KEY

db_keys="$(pm_service_secret_keys db)"
assert_contains "$db_keys" DB_USER
assert_contains "$db_keys" DB_ADMIN_PASSWORD
assert_not_contains "$db_keys" SUPPORT_CHANNEL_BOT_TOKEN

control_plane_keys="$(pm_secret_registry_keys_for_classification control-plane)"
assert_contains "$control_plane_keys" DB_API_KEY
assert_contains "$control_plane_keys" DNS_API_KEY
assert_not_contains "$control_plane_keys" SUPPORT_CHANNEL_BOT_TOKEN

canonical_keys="$(printf '%s\n' "${PM_CANONICAL_SECRET_KEYS[@]}")"
assert_contains "$canonical_keys" SUPPORT_CHANNEL_BOT_TOKEN
assert_contains "$canonical_keys" DB_API_KEY

PM_ADDITIONAL_SECRET_KEYS='PROJECT_ONLY_SECRET'
extended_keys="$(pm_service_secret_keys support-bot)"
assert_contains "$extended_keys" PROJECT_ONLY_SECRET

printf 'PASS: canonical secret registry classification and role injection\n'

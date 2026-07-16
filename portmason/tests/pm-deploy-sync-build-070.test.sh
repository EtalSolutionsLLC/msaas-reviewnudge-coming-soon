#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_file_exists() {
    local path="${1:?path required}"
    [[ -f "$path" ]] || fail "expected file: $path"
}

assert_path_absent() {
    local path="${1:?path required}"
    [[ ! -e "$path" ]] || fail "did not expect path: $path"
}

assert_contains() {
    local file="${1:?file required}"
    local expected="${2:?text required}"
    grep -Fq -- "$expected" "$file" || fail "expected '$expected' in $file"
}

sync_share="$temp_dir/portmason"
mkdir -p "$sync_share"
cp "$source_dir/pm-sync-deploy-from-root" "$sync_share/pm-sync-deploy-from-root"
cat >"$sync_share/pm-helpers" <<'EOF_HELPERS'
log() {
    local severity="${1:-INFO}"
    shift || true
    printf '[%s] %s\n' "$severity" "$*" >&2
}
error() { log ERROR "$@"; }
EOF_HELPERS
chmod +x "$sync_share/pm-sync-deploy-from-root"

# Load the implementation without invoking main so the canonical policy can be
# inspected directly.
PORTMASON_SHARE="$sync_share"
# shellcheck disable=SC1090
source "$sync_share/pm-sync-deploy-from-root"

[[ "${#PM_SYNC_EXCLUDE_PATTERNS[@]}" -gt 0 ]] \
    || fail 'canonical exclusion pattern array is empty'

declare -F is_excluded_directory_name >/dev/null \
    && fail 'legacy directory exclusion function still exists'
declare -F is_excluded_file_basename >/dev/null \
    && fail 'legacy file exclusion function still exists'
declare -F rsync_exclude_args >/dev/null \
    && fail 'legacy rsync exclusion generator still exists'

rsync_args=()
build_rsync_args rsync_args
[[ "${#rsync_args[@]}" -eq "${#PM_SYNC_EXCLUDE_PATTERNS[@]}" ]] \
    || fail 'rsync arguments were not derived one-for-one from the canonical array'

for index in "${!PM_SYNC_EXCLUDE_PATTERNS[@]}"; do
    expected="--exclude=${PM_SYNC_EXCLUDE_PATTERNS[$index]}"
    [[ "${rsync_args[$index]}" == "$expected" ]] \
        || fail "unexpected rsync exclusion at index $index"
done

repo="$temp_dir/repo"
env_dir="$repo/deploy/uat"
mkdir -p "$env_dir" "$repo/app" "$repo/src/logs" "$repo/tests" \
    "$repo/portmason" "$repo/archive" "$repo/artifact.bak"
git -C "$repo" init --quiet

printf 'managed-v1\n' >"$repo/app/main.txt"
printf 'root log\n' >"$repo/src/logs/root.log"
printf 'test fixture\n' >"$repo/tests/example.test"
printf 'tooling\n' >"$repo/portmason/tool"
printf 'archive\n' >"$repo/archive/item"
printf 'directory matched by file-style glob\n' >"$repo/artifact.bak/inside.txt"
printf 'secret\n' >"$repo/runtime.env"
printf 'example\n' >"$repo/runtime.env.example"
printf 'generated\n' >"$repo/runtime.env.generated"
printf 'dot env\n' >"$repo/.env"
printf 'dot env example\n' >"$repo/.env.example"
printf 'dot env generated\n' >"$repo/.env.generated"
printf 'container\n' >"$repo/Dockerfile.web"
printf 'bytecode\n' >"$repo/cache.pyc"
printf 'backup\n' >"$repo/settings.bak"
printf 'metadata\n' >"$repo/file.txt:Zone.Identifier"
printf 'mac\n' >"$repo/.DS_Store"
printf 'windows\n' >"$repo/Thumbs.db"
printf 'sync metadata\n' >"$repo/.pm-deploy-sync.shadow"

(
    cd "$env_dir"
    PORTMASON_SHARE="$sync_share" "$sync_share/pm-sync-deploy-from-root" --prepare
    PORTMASON_SHARE="$sync_share" "$sync_share/pm-sync-deploy-from-root" --finalize
)

assert_file_exists "$env_dir/app/main.txt"
[[ "$(cat "$env_dir/app/main.txt")" == 'managed-v1' ]] \
    || fail 'managed file content was not copied'

for excluded_path in \
    src/logs/root.log \
    tests/example.test \
    portmason/tool \
    archive/item \
    artifact.bak/inside.txt \
    runtime.env \
    runtime.env.example \
    runtime.env.generated \
    .env \
    .env.example \
    .env.generated \
    Dockerfile.web \
    cache.pyc \
    settings.bak \
    file.txt:Zone.Identifier \
    .DS_Store \
    Thumbs.db \
    .pm-deploy-sync.shadow; do
    assert_path_absent "$env_dir/$excluded_path"
done

# Environment-local changes matching the canonical exclusions must not count as
# drift, including a directory matched by a non-directory-specific glob.
mkdir -p "$env_dir/logs" "$env_dir/artifact.bak"
printf 'local log\n' >"$env_dir/logs/local.log"
printf 'local secret\n' >"$env_dir/local.env"
printf 'local dot env\n' >"$env_dir/.env"
printf 'local excluded directory\n' >"$env_dir/artifact.bak/local.txt"

(
    cd "$env_dir"
    PORTMASON_SHARE="$sync_share" "$sync_share/pm-sync-deploy-from-root" --status
) >"$temp_dir/status.out"
assert_contains "$temp_dir/status.out" 'Drift:       none'

# Root changes to excluded paths must not trigger copy-forward, while a managed
# root change still copies normally. Existing environment-local excluded paths
# must survive rsync --delete.
printf 'managed-v2\n' >"$repo/app/main.txt"
printf 'root log changed\n' >"$repo/src/logs/root.log"
printf 'root secret changed\n' >"$repo/runtime.env"
printf 'root dot env changed\n' >"$repo/.env"
printf 'root excluded directory changed\n' >"$repo/artifact.bak/inside.txt"

(
    cd "$env_dir"
    PORTMASON_SHARE="$sync_share" "$sync_share/pm-sync-deploy-from-root" --prepare
    PORTMASON_SHARE="$sync_share" "$sync_share/pm-sync-deploy-from-root" --finalize
)

[[ "$(cat "$env_dir/app/main.txt")" == 'managed-v2' ]] \
    || fail 'managed root change was not copied forward'
[[ "$(cat "$env_dir/logs/local.log")" == 'local log' ]] \
    || fail 'environment-local excluded file was deleted'
[[ "$(cat "$env_dir/local.env")" == 'local secret' ]] \
    || fail 'environment-local env file was deleted'
[[ "$(cat "$env_dir/.env")" == 'local dot env' ]] \
    || fail 'environment-local dot env file was deleted'
[[ "$(cat "$env_dir/artifact.bak/local.txt")" == 'local excluded directory' ]] \
    || fail 'environment-local excluded directory was deleted'
assert_path_absent "$env_dir/src/logs/root.log"
assert_path_absent "$env_dir/runtime.env"
assert_path_absent "$env_dir/artifact.bak/inside.txt"

printf 'Portmason deployment-sync Build 070 exclusion tests passed.\n'

#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    local file="${1:?file required}"
    local expected="${2:?text required}"
    grep -Fq -- "$expected" "$file" || fail "expected '$expected' in $file"
}

assert_not_contains() {
    local file="${1:?file required}"
    local unexpected="${2:?text required}"
    ! grep -Fq -- "$unexpected" "$file" || fail "did not expect '$unexpected' in $file"
}

# ---------------------------------------------------------------------------
# Actual synchronization lifecycle: drift blocks copy-forward, force is one-run.
# ---------------------------------------------------------------------------
sync_share="$temp_dir/sync-portmason"
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

repo="$temp_dir/repo"
mkdir -p "$repo/deploy/qas"
git -C "$repo" init --quiet
[[ ! -d "$repo/deploy/dev" ]] || fail 'DEV must remain the repository root rather than a synchronized deploy snapshot'
printf 'root-v1\n' >"$repo/application.txt"

(
    cd "$repo/deploy/qas"
    PORTMASON_SHARE="$sync_share" "$sync_share/pm-sync-deploy-from-root" --prepare
    PORTMASON_SHARE="$sync_share" "$sync_share/pm-sync-deploy-from-root" --finalize
)

[[ "$(cat "$repo/deploy/qas/application.txt")" == 'root-v1' ]] \
    || fail 'initial root synchronization did not complete'

printf 'qas-drift\n' >"$repo/deploy/qas/application.txt"
printf 'root-v2\n' >"$repo/application.txt"

set +e
(
    cd "$repo/deploy/qas"
    PORTMASON_SHARE="$sync_share" "$sync_share/pm-sync-deploy-from-root" --prepare
) >"$temp_dir/drift.out" 2>&1
rc=$?
set -e

[[ "$rc" -eq 3 ]] || fail "expected drift return code 3, received $rc"
[[ "$(cat "$repo/deploy/qas/application.txt")" == 'qas-drift' ]] \
    || fail 'drifted QAS file was overwritten without authorization'
[[ ! -e "$repo/deploy/qas/.pm-deploy-sync.in-progress" ]] \
    || fail 'drift path must not create an in-progress marker'
assert_contains "$temp_dir/drift.out" 'Deployment drift detected'
assert_contains "$temp_dir/drift.out" 'pm-setup may continue against the existing deployment snapshot.'

(
    cd "$repo/deploy/qas"
    PORTMASON_SHARE="$sync_share" "$sync_share/pm-sync-deploy-from-root" --prepare --force
    PORTMASON_SHARE="$sync_share" "$sync_share/pm-sync-deploy-from-root" --finalize
)

[[ "$(cat "$repo/deploy/qas/application.txt")" == 'root-v2' ]] \
    || fail 'explicit one-run refresh did not realign QAS from root'

printf 'qas-drift-again\n' >"$repo/deploy/qas/application.txt"
set +e
(
    cd "$repo/deploy/qas"
    PORTMASON_SHARE="$sync_share" "$sync_share/pm-sync-deploy-from-root" --prepare
) >"$temp_dir/drift-again.out" 2>&1
rc=$?
set -e
[[ "$rc" -eq 3 ]] || fail 'force authorization persisted beyond one invocation'
[[ "$(cat "$repo/deploy/qas/application.txt")" == 'qas-drift-again' ]] \
    || fail 'second drift was overwritten after one-run authorization was consumed'

# ---------------------------------------------------------------------------
# pm-setup orchestration: drift is caught; workflow continues; no finalize.
# ---------------------------------------------------------------------------
fake_share="$temp_dir/fake-portmason"
fake_repo="$temp_dir/setup-repo"
mkdir -p "$fake_share" "$fake_repo/deploy/qas"
git -C "$fake_repo" init --quiet
cp "$source_dir/pm-setup" "$fake_share/pm-setup"
chmod +x "$fake_share/pm-setup"

cat >"$fake_share/pm-helpers" <<'EOF_HELPERS'
PROJECT_ROOT="${PORTMASON_PROJECT_ROOT:?}"
export PROJECT_ROOT
declare -Ag PM_DB_LOADED_MODULES=()
log() { printf 'LOG %s\n' "$*"; }
warn() { printf 'WARN %s\n' "$*"; }
die() { printf 'DIE %s\n' "$*" >&2; return "${2:-1}"; }
fatal_error() { printf 'FATAL %s\n' "$*" >&2; exit "${2:-1}"; }
pm_setup_arg() { :; }
pm_commit_args() { :; }
pm_load_generated_environment() { :; }
pm_db_refresh_selectors() { :; }
pm_db_call_optional() { :; }
pm_db_has_configuration() { return 1; }
pm_db_preflight() { return 0; }
pm_db_load_helpers() { :; }
load_bridge_runtime_adapter() { :; }
load_adapter_helper() { :; }
load_runtime_helper() { :; }
stage_portmason() { printf 'MAINTENANCE_CONTINUED\n'; }
ensure_app_url() { APP_URL='https://example.test'; export APP_URL; }
EOF_HELPERS

cat >"$fake_share/pm-helpers-db" <<'EOF_DB'
# Test stub: database helpers are supplied by pm-helpers above.
EOF_DB

cat >"$fake_share/pm-generate-config" <<'EOF_CONFIG'
#!/usr/bin/env bash
printf 'CONFIG_GENERATED\n'
EOF_CONFIG
chmod +x "$fake_share/pm-generate-config"

cat >"$fake_share/pm-sync-deploy-from-root" <<'EOF_SYNC'
#!/usr/bin/env bash
case "${1:-}" in
    --prepare)
        printf 'PREPARE_DRIFT\n'
        exit 3
        ;;
    --finalize)
        printf 'UNEXPECTED_FINALIZE\n'
        exit 90
        ;;
esac
EOF_SYNC
chmod +x "$fake_share/pm-sync-deploy-from-root"

set +e
(
    cd "$fake_repo/deploy/qas"
    PORTMASON_SHARE="$fake_share" \
    APP_SLUG='reviewnudge' \
    STACK='reviewnudge-qas' \
    DEPLOY_ENV='qas' \
    RUNTIME_ADAPTER_CODE='static-local' \
        "$fake_share/pm-setup"
) >"$temp_dir/setup.out" 2>&1
setup_rc=$?
set -e
if [[ "$setup_rc" -ne 0 ]]; then
    cat "$temp_dir/setup.out" >&2
    fail "pm-setup drift continuation returned $setup_rc"
fi

assert_contains "$temp_dir/setup.out" 'PREPARE_DRIFT'
assert_contains "$temp_dir/setup.out" 'action=continue-existing-snapshot'
assert_contains "$temp_dir/setup.out" 'CONFIG_GENERATED'
assert_contains "$temp_dir/setup.out" 'MAINTENANCE_CONTINUED'
assert_contains "$temp_dir/setup.out" 'workflow complete'
assert_not_contains "$temp_dir/setup.out" 'UNEXPECTED_FINALIZE'

# ARM-file gating is intentionally removed from preflight.
assert_not_contains "$source_dir/pm-helpers-db" 'ALLOW_PROD_DEPLOY.on'
assert_not_contains "$source_dir/pm-helpers-db" 'PM_PROD_ARM_FILE'
assert_not_contains "$source_dir/pm-helpers-db" 'safety.arm'
assert_not_contains "$source_dir/pm-helpers-db" 'pm_preflight_validate_prod_arm'

printf 'Portmason deploy synchronization Build 069 tests passed.\n'

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PORTMASON_SHARE="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
REPO_ROOT="$(cd -- "${PORTMASON_SHARE}/../.." && pwd -P)"
export PORTMASON_SHARE

pass_count=0
fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}
pass() {
    pass_count=$((pass_count + 1))
    printf 'PASS: %s\n' "$*"
}
assert_contains() {
    local haystack="${1-}" needle="${2:?needle required}" label="${3:?label required}"
    [[ "$haystack" == *"$needle"* ]] || fail "$label: missing '$needle'"
    pass "$label"
}
assert_not_contains() {
    local haystack="${1-}" needle="${2:?needle required}" label="${3:?label required}"
    [[ "$haystack" != *"$needle"* ]] || fail "$label: unexpectedly contained '$needle'"
    pass "$label"
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v unzip >/dev/null 2>&1 || fail "unzip is required"

"${PORTMASON_SHARE}/pm-patterns" validate
pass "pattern registry validates"
patterns_output="$("${PORTMASON_SHARE}/pm-patterns" search navigation)"
assert_contains "$patterns_output" "PM-PAT-008" "pattern search finds canonical viewport navigation"
pattern_show="$("${PORTMASON_SHARE}/pm-patterns" show PM-PAT-006)"
assert_contains "$pattern_show" "Snapshot-first modification" "pattern show returns preservation contract"

"${PORTMASON_SHARE}/pm-capabilities" validate
pass "capability catalog validates and cross-references known patterns"
capabilities_output="$("${PORTMASON_SHARE}/pm-capabilities" search navigation)"
assert_contains "$capabilities_output" "pm-viewport-navigation" "capability search finds viewport utility"
capability_show="$("${PORTMASON_SHARE}/pm-capabilities" show pm-config-manager)"
assert_contains "$capability_show" "scoped local env files" "capability show returns outputs"

fixture_root="$(mktemp -d)"
trap 'rm -rf "$fixture_root"' EXIT

valid_manifest="${fixture_root}/preservation.json"
cat > "$valid_manifest" <<'JSON'
{
  "schemaVersion": "1.0",
  "migrationId": "BUILD-999-fixture",
  "createdAt": "2026-07-08",
  "sourceSnapshot": {
    "file": "fixture_2026-07-08T00-00-00-0700.tar.gz",
    "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  },
  "preserved": {
    "services": ["web"],
    "volumes": ["data"],
    "routes": ["/"],
    "environmentKeys": ["APP_SLUG"]
  },
  "renamed": {"OLD_KEY": "PM_NEW_KEY"},
  "removed": [{"item": "OLD_KEY", "reason": "Replaced by canonical PM configuration."}],
  "added": ["project/preservation.json"],
  "verification": ["docker compose config --quiet"]
}
JSON
"${PORTMASON_SHARE}/pm-preservation-manifest" validate "$valid_manifest"
pass "preservation command validates a complete manifest"
summary="$("${PORTMASON_SHARE}/pm-preservation-manifest" summary "$valid_manifest")"
assert_contains "$summary" "BUILD-999-fixture" "preservation summary identifies migration"

viewport_root="${fixture_root}/viewport"
mkdir -p "$viewport_root/www"
cat > "$viewport_root/.env" <<'EOF_ENV'
RUNTIME_ADAPTER_CODE=static-local
EOF_ENV
cat > "$viewport_root/www/site.js" <<'EOF_JS'
document.querySelector('#top').scrollIntoView({ behavior: 'smooth' });
EOF_JS
viewport_result="$("${PORTMASON_SHARE}/pm-lint" --root "$viewport_root" --all --rule PM023 --format text || true)"
assert_contains "$viewport_result" "[PM023]" "PM023 detects local viewport implementation"
cat > "$viewport_root/www/index.html" <<'EOF_HTML'
<script src="/assets/pm-viewport-navigation.js"></script>
EOF_HTML
viewport_result="$("${PORTMASON_SHARE}/pm-lint" --root "$viewport_root" --all --rule PM023 --format text || true)"
assert_not_contains "$viewport_result" "[PM023]" "PM023 accepts canonical viewport capability"

content_root="${fixture_root}/content"
mkdir -p "$content_root/www"
cat > "$content_root/www/index.html" <<'EOF_HTML'
<h1>Review requests without the awkward follow-up.</h1>
<p>Collect useful customer feedback with a simple workflow.</p>
<button>Notify me when early access opens</button>
EOF_HTML
content_result="$("${PORTMASON_SHARE}/pm-lint" --root "$content_root" --all --rule PM024 --format text || true)"
assert_contains "$content_result" "[PM024]" "PM024 identifies embedded visitor copy"
cat > "$content_root/www/index.html" <<'EOF_HTML'
<h1 data-content-key="hero.title"></h1>
<p data-content-key="hero.body"></p>
<button data-content-key="hero.cta"></button>
<script src="/assets/content.js"></script>
EOF_HTML
content_result="$("${PORTMASON_SHARE}/pm-lint" --root "$content_root" --all --rule PM024 --format text || true)"
assert_not_contains "$content_result" "[PM024]" "PM024 accepts catalog-driven content"

order_root="${fixture_root}/order"
mkdir -p "$order_root/ops/portmason"
cat > "$order_root/ops/portmason/pm-setup" <<'EOF_BAD'
#!/usr/bin/env bash
set -euo pipefail
pm_db_preflight
pm_config_manager_bootstrap_local_env_files
EOF_BAD
order_result="$("${PORTMASON_SHARE}/pm-lint" --root "$order_root" --all --rule PM025 --format text || true)"
assert_contains "$order_result" "[PM025]" "PM025 rejects late config bootstrap"
cat > "$order_root/ops/portmason/pm-setup" <<'EOF_GOOD'
#!/usr/bin/env bash
set -euo pipefail
pm_config_manager_bootstrap_local_env_files
pm_db_preflight
EOF_GOOD
order_result="$("${PORTMASON_SHARE}/pm-lint" --root "$order_root" --all --rule PM025 --format text || true)"
assert_not_contains "$order_result" "[PM025]" "PM025 accepts preflight-safe ordering"

migration_root="${fixture_root}/migration"
mkdir -p "$migration_root/project"
cat > "$migration_root/chg.txt" <<'EOF_CHG'
project/.env
project/docker-compose.yml
EOF_CHG
migration_result="$("${PORTMASON_SHARE}/pm-lint" --root "$migration_root" --all --rule PM026 --format text || true)"
assert_contains "$migration_result" "[PM026]" "PM026 requires preservation evidence"
cp "$valid_manifest" "$migration_root/project/preservation.json"
migration_result="$("${PORTMASON_SHARE}/pm-lint" --root "$migration_root" --all --rule PM026 --format text || true)"
assert_not_contains "$migration_result" "[PM026]" "PM026 accepts preservation evidence"
manifest_result="$("${PORTMASON_SHARE}/pm-lint" --root "$migration_root" --all --rule PM027 --format text || true)"
assert_not_contains "$manifest_result" "[PM027]" "PM027 accepts valid preservation schema"
printf '{"schemaVersion":"1.0"}\n' > "$migration_root/project/preservation.json"
manifest_result="$("${PORTMASON_SHARE}/pm-lint" --root "$migration_root" --all --rule PM027 --format text || true)"
assert_contains "$manifest_result" "[PM027]" "PM027 rejects incomplete preservation schema"

TGF="${REPO_ROOT}/sops/TGF-v1.12.docx"
[[ -r "$TGF" ]] || fail "TGF v1.12 is missing"
tgf_xml="$(unzip -p "$TGF" word/document.xml)"
assert_contains "$tgf_xml" "Pattern Governance and Canonicalization" "TGF contains pattern-governance policy"
assert_contains "$tgf_xml" "A2.10) Pattern Reuse and Promotion" "EPC contains pattern reuse contract"
assert_contains "$tgf_xml" "A12.8) Snapshot and Migration Preservation" "EPC contains migration preservation contract"
assert_contains "$tgf_xml" "v1.12 (Current)" "TGF changelog identifies v1.12 as current"

printf 'PM canonicalization Build 092: %d checks passed.\n' "$pass_count"

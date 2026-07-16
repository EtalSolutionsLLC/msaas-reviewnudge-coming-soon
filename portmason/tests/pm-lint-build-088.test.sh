#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PORTMASON_SHARE="$(cd -- "${TEST_DIR}/.." && pwd -P)"
export PORTMASON_SHARE

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

pass_count=0

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

pass() {
    pass_count=$((pass_count + 1))
    printf 'PASS: %s\n' "$*"
}

new_repo() {
    local name="${1:?name required}"
    local repo="${TMP_ROOT}/${name}"
    mkdir -p "$repo/ops/portmason" "$repo/tests" "$repo/.github/workflows"
    printf '# Fixture\n' > "$repo/README.md"
    printf '#!/usr/bin/env bash\nset -euo pipefail\n' > "$repo/tests/smoke.test.sh"
    printf 'name: fixture\n' > "$repo/.github/workflows/test.yml"
    git -C "$repo" init -q
    git -C "$repo" config user.email test@example.invalid
    git -C "$repo" config user.name 'PM Lint Test'
    printf '%s' "$repo"
}

run_lint() {
    local repo="${1:?repo required}"
    shift
    (
        cd "$repo"
        PM_LINT_ASSUME_TRACKED=true \
            bash "${PORTMASON_SHARE}/pm-lint" --root "$repo" "$@"
    )
}

assert_failure_contains() {
    local expected="${1:?expected text required}"
    shift
    local output="" rc=0
    output="$($@ 2>&1)" || rc=$?
    (( rc != 0 )) || fail "expected command to fail: $*"
    grep -Fq "$expected" <<<"$output" \
        || fail "expected failure output to contain '$expected'; output: $output"
}

assert_success_contains() {
    local expected="${1:?expected text required}"
    shift
    local output=""
    output="$($@ 2>&1)" || fail "expected command to pass: $*; output: $output"
    grep -Fq "$expected" <<<"$output" \
        || fail "expected success output to contain '$expected'; output: $output"
}

# Rule catalog loads and exposes stable IDs.
repo="$(new_repo catalog)"
output="$(run_lint "$repo" --list-rules)"
grep -Fq $'PM001\tERROR\tfile' <<<"$output" || fail 'PM001 missing from catalog'
grep -Fq $'PM016\tREVIEW\tfile' <<<"$output" || fail 'PM016 missing from catalog'
[[ "$(grep -c '^PM[0-9][0-9][0-9]' <<<"$output")" -eq 28 ]] || fail 'expected 28 registered rules'
grep -Fq $'PM020\tWARNING\tfile' <<<"$output" || fail 'PM020 missing from catalog'
grep -Fq $'PM021\tERROR\tfile' <<<"$output" || fail 'PM021 missing from catalog'
grep -Fq $'PM022\tGUIDANCE\tfile' <<<"$output" || fail 'PM022 missing from catalog'
grep -Fq $'PM027\tERROR\tfile' <<<"$output" || fail 'PM027 missing from catalog'
grep -Fq $'PM027\tERROR\tfile' <<<"$output" || fail 'PM027 missing from catalog'
pass 'rule catalog'

# Project-local rules are discovered without engine changes and use PM900-PM999.
repo="$(new_repo custom-rules)"
mkdir -p "$repo/.pm-lint/rules"
cat > "$repo/.pm-lint/rules/pm-lint-rule-pm900-fixture" <<'FILE'
#!/usr/bin/env bash
set -euo pipefail
pm_lint_rule_pm900() {
    local path="${1:?path required}"
    local file="${2:?file required}"
    grep -q 'custom-violation' "$file" || return 0
    pm_lint_report PM900 "$path" 1 "Custom fixture violation" "Use the project convention."
}
pm_lint_register_rule PM900 ERROR file "Custom fixture" "Project policy" pm_lint_rule_pm900
FILE
printf 'custom-violation\n' > "$repo/custom.txt"
assert_failure_contains PM900 run_lint "$repo" custom.txt
output="$(run_lint "$repo" --list-rules)"
grep -Fq $'PM900\tERROR\tfile' <<<"$output" || fail 'project custom rule was not loaded'
pass 'project rule extension'

# Project rules may not consume canonical rule IDs.
repo="$(new_repo invalid-custom-id)"
mkdir -p "$repo/.pm-lint/rules"
cat > "$repo/.pm-lint/rules/pm-lint-rule-pm100-invalid" <<'FILE'
#!/usr/bin/env bash
set -euo pipefail
pm_lint_rule_pm100() { :; }
pm_lint_register_rule PM100 ERROR project "Invalid custom id" "Project policy" pm_lint_rule_pm100
FILE
assert_failure_contains 'PM900-PM999' run_lint "$repo" --list-rules
pass 'custom rule id boundary'

# Read-only bootstrap must not scaffold .env or identity files.
repo="$(new_repo readonly)"
rm -f "$repo/.env" "$repo/.project_timestamp"
run_lint "$repo" --list-rules >/dev/null
[[ ! -e "$repo/.env" && ! -e "$repo/.project_timestamp" ]] \
    || fail 'read-only bootstrap mutated project state'
pass 'read-only bootstrap'

# PM001 namespacing.
repo="$(new_repo namespace)"
cat > "$repo/ops/portmason/custom-tool" <<'FILE'
#!/usr/bin/env bash
set -euo pipefail
main() { :; }
main "$@"
FILE
assert_failure_contains PM001 run_lint "$repo" --rule PM001 ops/portmason/custom-tool
pass 'PM001 namespace'

# PM002 strict Bash contract.
repo="$(new_repo bash-contract)"
cat > "$repo/ops/portmason/pm-bad" <<'FILE'
#!/bin/bash
echo broken
FILE
assert_failure_contains PM002 run_lint "$repo" --rule PM002 ops/portmason/pm-bad
cat > "$repo/ops/portmason/pm-good" <<'FILE'
#!/usr/bin/env bash
set -euo pipefail
main() { :; }
main "$@"
FILE
run_lint "$repo" --rule PM002 ops/portmason/pm-good >/dev/null || fail 'valid Bash contract failed'
pass 'PM002 Bash contract'

# PM003 warnings become blocking only in strict mode.
repo="$(new_repo logging)"
cat > "$repo/ops/portmason/pm-logging" <<'FILE'
#!/usr/bin/env bash
set -euo pipefail
main() {
    echo "hello"
}
main "$@"
FILE
assert_success_contains PM003 run_lint "$repo" --rule PM003 ops/portmason/pm-logging
assert_failure_contains PM003 run_lint "$repo" --strict --rule PM003 ops/portmason/pm-logging
pass 'PM003 strict warning behavior'

# PM004 config signature.
repo="$(new_repo config-signature)"
cat > "$repo/ops/portmason/pm-config-cloudflared" <<'FILE'
#!/usr/bin/env bash
set -euo pipefail
pm_config_wrong() { :; }
FILE
assert_failure_contains pm_config_cloudflared run_lint "$repo" --rule PM004 ops/portmason/pm-config-cloudflared
sed -i 's/pm_config_wrong/pm_config_cloudflared/' "$repo/ops/portmason/pm-config-cloudflared"
run_lint "$repo" --rule PM004 ops/portmason/pm-config-cloudflared >/dev/null || fail 'valid config signature failed'
pass 'PM004 config signature'

# PM005 source safety.
repo="$(new_repo source-safety)"
cat > "$repo/ops/portmason/pm-helpers-example" <<'FILE'
#!/usr/bin/env bash
set -euo pipefail
main() { :; }
main "$@"
FILE
assert_failure_contains PM005 run_lint "$repo" --rule PM005 ops/portmason/pm-helpers-example
pass 'PM005 source safety'

# PM006 and PM017 selector/database authority.
repo="$(new_repo selectors)"
cat > "$repo/project.env" <<'FILE'
RUNTIME_ADAPTER_CODE=node-gcp
RUNTIME_CODE=node
ADAPTER_CODE=gcp
DB_PROVIDER_PLATFORM_CODE=postgres-neon
DB_PROVIDER_CODE=postgres
DB_PLATFORM_CODE=neon
DATABASE_URL=postgres://example
FILE
assert_failure_contains PM006 run_lint "$repo" --rule PM006 project.env
assert_failure_contains PM017 run_lint "$repo" --rule PM017 project.env
pass 'PM006 and PM017 source-of-truth rules'


# PM007 production flows may not pass env files to runtimes.
repo="$(new_repo production-env)"
cat > "$repo/deploy-prd.sh" <<'FILE'
#!/usr/bin/env bash
set -euo pipefail
docker compose --env-file prd.env up -d
FILE
assert_failure_contains PM007 run_lint "$repo" --rule PM007 deploy-prd.sh
pass 'PM007 production env-file prohibition'

# PM008 Compose naming.
repo="$(new_repo compose)"
cat > "$repo/docker-compose.yml" <<'FILE'
services:
  web:
    container_name: bad
    image: example.invalid/web:latest
FILE
assert_failure_contains PM008 run_lint "$repo" --rule PM008 docker-compose.yml
cat > "$repo/docker-compose.yml" <<'FILE'
name: ${STACK}
services:
  web:
    image: example.invalid/web:latest
FILE
run_lint "$repo" --rule PM008 docker-compose.yml >/dev/null || fail 'valid Compose identity failed'
pass 'PM008 Compose identity'

# PM009 deprecated label namespace.
repo="$(new_repo labels)"
cat > "$repo/docker-compose.yml" <<'FILE'
name: ${STACK}
services:
  web:
    image: example.invalid/web:latest
    labels:
FILE
printf '      %s.stack: ${STACK}\n' 'com.etalsolutions' >> "$repo/docker-compose.yml"
assert_failure_contains PM009 run_lint "$repo" --rule PM009 docker-compose.yml
pass 'PM009 label namespace'


# PM010 validates required labels per service, not merely per file.
repo="$(new_repo compose-labels)"
cat > "$repo/docker-compose.yml" <<'FILE'
name: ${STACK}
services:
  labeled:
    image: example.invalid/labeled:latest
    labels:
      solutions.etal.project_id: ${PROJECT_ID}
      solutions.etal.stack: ${STACK}
      solutions.etal.deployment_id: ${DEPLOYMENT_ID}
      solutions.etal.service: worker
  unlabeled:
    image: example.invalid/unlabeled:latest
FILE
assert_success_contains "service 'unlabeled'" run_lint "$repo" --rule PM010 docker-compose.yml
assert_failure_contains PM010 run_lint "$repo" --strict --rule PM010 docker-compose.yml
cat > "$repo/docker-compose.yml" <<'FILE'
name: ${STACK}
services:
  web:
    image: example.invalid/web:latest
    labels:
      solutions.etal.project_id: ${PROJECT_ID}
      solutions.etal.stack: ${STACK}
      solutions.etal.deployment_id: ${DEPLOYMENT_ID}
      solutions.etal.service: web
FILE
run_lint "$repo" --strict --rule PM010 docker-compose.yml >/dev/null || fail 'valid per-service labels failed'
pass 'PM010 per-service Compose labels'

# PM012 health/readiness evidence.
repo="$(new_repo health)"
cat > "$repo/docker-compose.yml" <<'FILE'
name: ${STACK}
services:
  web:
    image: example.invalid/web:latest
    labels:
      solutions.etal.service: web
FILE
assert_failure_contains PM012 run_lint "$repo" --strict --rule PM012 docker-compose.yml
printf '%s\n' '/healthz' '/readyz' > "$repo/health-contract.txt"
run_lint "$repo" --strict --rule PM012 docker-compose.yml >/dev/null || fail 'health evidence should satisfy PM012'
pass 'PM012 health and readiness'

# PM013 repository baseline.
repo="${TMP_ROOT}/project-baseline"
mkdir -p "$repo"
git -C "$repo" init -q
assert_failure_contains PM013 run_lint "$repo" --strict --rule PM013
repo="$(new_repo project-baseline-valid)"
run_lint "$repo" --strict --rule PM013 >/dev/null || fail 'valid project baseline failed'
pass 'PM013 project baseline'

# PM014 bridge-boundary guidance.
repo="$(new_repo bridge-boundary)"
cat > "$repo/ops/portmason/pm-deploy-node" <<'FILE'
#!/usr/bin/env bash
set -euo pipefail
pm_deploy_node() {
    : "${RUNTIME_CODE:?}"
    : "${ADAPTER_CODE:?}"
}
FILE
assert_success_contains PM014 run_lint "$repo" --rule PM014 ops/portmason/pm-deploy-node
pass 'PM014 bridge-boundary guidance'

# PM011 committed secret detection.
repo="$(new_repo secrets)"
printf 'PM_EDGE_TUNNEL_TOKEN=fixture-%s-token-value\nDATABASE_URL=postgres://user:pass@db.internal/db\n' "$RANDOM" > "$repo/.env"
git -C "$repo" add .env
assert_failure_contains PM011 run_lint "$repo" --rule PM011 .env
assert_failure_contains DATABASE_URL run_lint "$repo" --rule PM011 .env
pass 'PM011 secret detection'

# PM015 Portmason-owned prefix and provider-native source detection.
repo="$(new_repo pm-prefix)"
cat > "$repo/project.env" <<'FILE'
SUPPORT_CHANNEL_PROVIDER=slack
TUNNEL_TOKEN=do-not-author-provider-native-values
FILE
assert_failure_contains PM015 run_lint "$repo" --rule PM015 project.env
pass 'PM015 PM_ namespace'

# PM016 emerging pattern review: non-blocking by default, blockable by policy.
repo="$(new_repo new-pattern)"
cat > "$repo/ops/portmason/pm-mystery-layer" <<'FILE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${__PM_MYSTERY_LOADED:-0}" == 1 ]]; then
    return 0 2>/dev/null || exit 0
fi
__PM_MYSTERY_LOADED=1
pm_mystery_capability() { :; }
FILE
assert_success_contains PM016 run_lint "$repo" --rule PM016 ops/portmason/pm-mystery-layer
assert_failure_contains PM016 run_lint "$repo" --fail-on-review --rule PM016 ops/portmason/pm-mystery-layer
pass 'PM016 new-pattern review'


# PM018 evaluates the database service block rather than unrelated ports.
repo="$(new_repo compose-guidance)"
cat > "$repo/docker-compose.yml" <<'FILE'
name: ${STACK}
services:
  db:
    image: postgres:17
    labels:
      solutions.etal.service: db
  proxy:
    image: traefik:v3
    ports:
      - "127.0.0.1:443:443"
    labels:
      solutions.etal.service: proxy
FILE
output="$(run_lint "$repo" --rule PM018 docker-compose.yml)"
grep -Fq PM018 <<<"$output" && fail 'PM018 falsely attributed proxy ports to database service'
sed -i '/image: postgres:17/a\    ports:\n      - "5432:5432"' "$repo/docker-compose.yml"
assert_success_contains PM018 run_lint "$repo" --rule PM018 docker-compose.yml
pass 'PM018 database service isolation'

# PM019 targets broad application roles without explicit scopes.
repo="$(new_repo config-scopes)"
cat > "$repo/docker-compose.yml" <<'FILE'
name: ${STACK}
services:
  web:
    image: example.invalid/web:latest
    labels:
      solutions.etal.service: web
  db:
    image: postgres:17
    labels:
      solutions.etal.service: db
FILE
assert_success_contains "service 'web'" run_lint "$repo" --rule PM019 docker-compose.yml
pass 'PM019 service-scoped configuration'

# PM021 blocks alternate public entrypoints; PM022 guides Traefik routing.
repo="$(new_repo single-front-door)"
cat > "$repo/docker-compose.yml" <<'FILE'
name: ${STACK}
services:
  web:
    image: example.invalid/web:latest
    ports:
      - "8080:8080"
    labels:
      solutions.etal.service: web
FILE
assert_failure_contains PM021 run_lint "$repo" --rule PM021 docker-compose.yml
assert_success_contains PM022 run_lint "$repo" --rule PM022 docker-compose.yml
sed -i '/ports:/,+1d' "$repo/docker-compose.yml"
sed -i '/solutions.etal.service: web/a\      traefik.enable: "true"' "$repo/docker-compose.yml"
run_lint "$repo" --rule PM021 docker-compose.yml >/dev/null || fail 'PM021 rejected ingress-only service'
output="$(run_lint "$repo" --rule PM022 docker-compose.yml)"
grep -Fq PM022 <<<"$output" && fail 'PM022 rejected explicit Traefik routing'
pass 'PM021 and PM022 ingress contract'

# PM020 delegates shell static analysis to ShellCheck when available.
repo="$(new_repo shellcheck)"
mkdir -p "$TMP_ROOT/fake-bin"
cat > "$TMP_ROOT/fake-bin/shellcheck" <<'FILE'
#!/usr/bin/env bash
set -euo pipefail
file="${@: -1}"
printf '%s:3:1: warning: simulated defect [SC9999]\n' "$file"
exit 1
FILE
chmod +x "$TMP_ROOT/fake-bin/shellcheck"
cat > "$repo/ops/portmason/pm-shellcheck-fixture" <<'FILE'
#!/usr/bin/env bash
set -euo pipefail
value=fixture
FILE
output=""
rc=0
output="$(PATH="$TMP_ROOT/fake-bin:$PATH" run_lint "$repo" --strict --rule PM020 ops/portmason/pm-shellcheck-fixture 2>&1)" || rc=$?
(( rc != 0 )) || fail 'PM020 did not block a ShellCheck warning under strict mode'
grep -Fq 'SC9999' <<<"$output" || fail "PM020 did not preserve ShellCheck diagnostic: $output"
pass 'PM020 ShellCheck integration'

# Valid exception suppresses a concrete finding.
repo="$(new_repo exceptions)"
cat > "$repo/ops/portmason/pm-bad" <<'FILE'
#!/bin/bash
echo broken
FILE
cat > "$repo/.pm-lint-exceptions" <<'FILE'
PM002|ops/portmason/pm-bad|Test Owner|2026-07-08|2099-12-31|Fixture verifies explicit suppression
FILE
output="$(run_lint "$repo" --rule PM002 ops/portmason/pm-bad)" || fail 'valid exception did not suppress finding'
grep -Fq '2 suppressed' <<<"$output" || fail 'suppressed count missing'
pass 'valid exception'

# Expired exception is a blocking PM000 finding.
repo="$(new_repo expired-exception)"
cat > "$repo/ops/portmason/pm-good" <<'FILE'
#!/usr/bin/env bash
set -euo pipefail
main() { :; }
main "$@"
FILE
cat > "$repo/.pm-lint-exceptions" <<'FILE'
PM002|ops/portmason/pm-good|Test Owner|2020-01-01|2020-02-01|Expired fixture
FILE
assert_failure_contains PM000 run_lint "$repo" --rule PM002 ops/portmason/pm-good
pass 'expired exception'

# Unknown and repository-wide exceptions are rejected.
repo="$(new_repo invalid-exception)"
cat > "$repo/.pm-lint-exceptions" <<'FILE'
PM899|*|Test Owner|2026-07-08|2099-12-31|Fixture intentionally uses an invalid exception
FILE
assert_failure_contains PM000 run_lint "$repo" --all
cat > "$repo/.pm-lint-exceptions" <<'FILE'
PM002|*|Test Owner|2026-07-08|2099-12-31|Fixture intentionally uses an overly broad exception
FILE
assert_failure_contains 'overly broad' run_lint "$repo" --all
pass 'exception integrity'

# JSON output is valid and contains structured findings.
repo="$(new_repo json)"
cat > "$repo/project.env" <<'FILE'
RUNTIME_CODE=node
FILE
json_output="$(run_lint "$repo" --format json --rule PM006 project.env 2>/dev/null)" || true
jq -e '.summary.errors == 1 and .findings[0].rule == "PM006"' >/dev/null <<<"$json_output" \
    || fail "invalid JSON output: $json_output"
pass 'JSON output'

# Every delivered Bash file parses.
while IFS= read -r -d '' file; do
    bash -n "$file" || fail "bash -n failed: $file"
done < <(find "$PORTMASON_SHARE" -maxdepth 3 -type f \
    \( -name 'pm-lint*' -o -name 'pm-helpers-lint' -o -path '*/lint/rules/*' -o -path '*/lint/templates/*' \) -print0)
pass 'delivered Bash syntax'

printf 'PASS: PM Lint Build 088 (%d checks)\n' "$pass_count"

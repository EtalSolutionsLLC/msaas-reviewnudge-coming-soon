#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PORTMASON_SHARE="$(cd -- "${TEST_DIR}/.." && pwd -P)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

workspace="$TMP_DIR/workspace"
mkdir -p "$workspace/traefik" "$workspace/msaas-reviewnudge-coming-soon" "$workspace/msaas-reviewnudge"
cat >"$workspace/traefik/.env" <<'ENV'
APP_SLUG=traefik
ENV
cat >"$workspace/msaas-reviewnudge-coming-soon/.env" <<'ENV'
APP_SLUG=reviewnudge-coming-soon
ENV
cat >"$workspace/msaas-reviewnudge/.env" <<'ENV'
APP_SLUG=reviewnudge
ENV

for project in traefik msaas-reviewnudge-coming-soon msaas-reviewnudge; do
    git -C "$workspace/$project" init -q
    : >"$workspace/$project/docker-compose.yml"
done

output="$TMP_DIR/output.log"
PORTMASON_SHARE="$PORTMASON_SHARE" \
    "${PORTMASON_SHARE}/pm-launch-reviewnudge" \
    --workspace "$workspace" \
    --skip-migrations \
    --skip-endpoints \
    --dry-run >"$output" 2>&1

traefik_line="$(grep -n 'deployment start project=traefik ' "$output" | cut -d: -f1)"
coming_line="$(grep -n 'deployment start project=coming-soon ' "$output" | cut -d: -f1)"
reviewnudge_line="$(grep -n 'deployment start project=reviewnudge ' "$output" | cut -d: -f1)"

[[ -n "$traefik_line" && -n "$coming_line" && -n "$reviewnudge_line" ]] || {
    cat "$output" >&2
    printf 'FAIL: launch plan did not include all three projects\n' >&2
    exit 1
}
[[ "$traefik_line" -lt "$coming_line" && "$coming_line" -lt "$reviewnudge_line" ]] || {
    cat "$output" >&2
    printf 'FAIL: projects were not deployed in dependency order\n' >&2
    exit 1
}

grep -q 'docker compose up -d --build --remove-orphans' "$output" || {
    cat "$output" >&2
    printf 'FAIL: launch does not recreate services and remove orphans\n' >&2
    exit 1
}
grep -q 'Nudge launch complete' "$output" || {
    cat "$output" >&2
    printf 'FAIL: launch did not reach completion\n' >&2
    exit 1
}

printf 'PASS: Nudge launch conductor discovers projects and preserves deployment order\n'

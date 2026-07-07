#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM
mkdir -p "$temp_dir/bin" "$temp_dir/project"

log() { :; }
die() { return "${2:-1}"; }
have() { command -v "$1" >/dev/null 2>&1; }
env_init_set() { printf -v "$1" '%s' "${2-}"; export "$1"; }
export -f log die have env_init_set

cat > "$temp_dir/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
if [[ "$1" == "compose" && "$2" == "-f" && "$4" == "config" && "$5" == "--format" && "$6" == "json" ]]; then
    printf 'invalid interpolation format for services.cloudflared.command.\n' >&2
    printf 'You may need to escape PM_NETWORK_TUNNEL_TOKEN.\n' >&2
    printf 'PM_NETWORK_TUNNEL_TOKEN=super-secret-value\n' >&2
    exit 14
fi
printf 'unexpected docker invocation: %s\n' "$*" >&2
exit 99
DOCKER
chmod +x "$temp_dir/bin/docker"
PATH="$temp_dir/bin:$PATH"

cat > "$temp_dir/bin/jq" <<'JQ'
#!/usr/bin/env bash
cat >/dev/null
exit 0
JQ
chmod +x "$temp_dir/bin/jq"

export PORTMASON_SHARE="$source_dir"
export SCRIPT_DIR="$temp_dir/project"
export PM_COMPOSE_FILE="$temp_dir/project/docker-compose.yml"
export PM_COMPOSE_OVERRIDE_FILE="$temp_dir/project/docker-compose.override.yml"
: > "$PM_COMPOSE_FILE"

. "$source_dir/pm-helpers-db"
pm_preflight_reset

if pm_compose_load_model; then
    printf 'Expected compose model loading to fail.\n' >&2
    exit 1
fi

joined="$(printf '%s\n' "${PM_PREFLIGHT_ERRORS[@]}")"
grep -Fq 'compose.model|docker-compose.yml|could not be rendered by:' <<<"$joined"
grep -Fq 'docker compose -f' <<<"$joined"
grep -Fq 'invalid interpolation format' <<<"$joined"
grep -Fq 'PM_NETWORK_TUNNEL_TOKEN=***REDACTED***' <<<"$joined"
! grep -Fq 'super-secret-value' <<<"$joined"

printf 'Portmason compose render diagnostics test passed.\n'

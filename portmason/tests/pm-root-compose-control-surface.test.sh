#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM

repo="$temp_dir/project"
mkdir -p "$repo/deploy/prd"
git -C "$repo" init --quiet
cat >"$repo/docker-compose.yml" <<'YAML'
services:
  web:
    image: alpine:3.22
    env_file:
      - .runtime.env
YAML
printf 'CONTROL_SURFACE_TEST=active-environment\n' >"$repo/deploy/prd/.runtime.env"

context="$({
    cd "$repo/deploy/prd"
    PORTMASON_SHARE="$root" "$root/pm-setup" --bootstrap-context
})"

grep -Fq "PROJECT_ROOT=$repo" <<<"$context"
grep -Fq "SCRIPT_DIR=$repo/deploy/prd" <<<"$context"
grep -Fq "PM_COMPOSE_CONTROL_FILE=$repo/docker-compose.yml" <<<"$context"
grep -Fq "PM_COMPOSE_PROJECT_DIRECTORY=$repo/deploy/prd" <<<"$context"

model="$(docker compose \
    --project-directory "$repo/deploy/prd" \
    -f "$repo/docker-compose.yml" \
    config --format json)"
[[ "$(jq -r '.services.web.environment.CONTROL_SURFACE_TEST' <<<"$model")" == active-environment ]]

grep -Fq 'pm_compose_control_file compose_file' "$root/pm-setup"
grep -Fq -- '--project-directory "$project_directory"' "$root/pm-setup"
grep -Fq -- '--project-directory "$project_directory"' "$root/pm-helpers-db"
grep -Fq 'pm_compose_control_file compose_file' "$root/pm-config-manager"
grep -Fq '"docker-compose.yml"' "$root/pm-sync-deploy-from-root" \
    && { printf 'deploy sync must not exclude the root Compose control surface\n' >&2; exit 1; }
grep -Fq 'canonical_model=' "$root/pm-deploy-gcp" \
    && { printf 'GCP adapter must not reconstruct a second Compose model\n' >&2; exit 1; }
grep -Fq '"${PM_COMPOSE_CMD[@]}" config \' "$root/pm-ensure-external-networks"
grep -Fq -- '--no-interpolate' "$root/pm-ensure-external-networks"
grep -Fq -- '--no-env-resolution' "$root/pm-ensure-external-networks"
grep -Fq 'pm_compose_init_command' "$root/pm-get-compose-images"
grep -Fq 'pm_compose_init_command' "$root/pm-dbmigrate-dotnet-local"
grep -Fq 'pm_compose_init_command' "$root/pm-refresh-traefik"
grep -Fq 'pm-update-docker-env-file is retired' "$root/pm-update-docker-env-file"
grep -Fq 'set-docker-env-file is retired' "$root/pm-helpers-base"

printf 'PASS: repository-root Compose is the Portmason control surface.\n'

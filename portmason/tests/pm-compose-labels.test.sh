#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM

cat >"$temp_dir/.env.generated" <<'ENV'
MANAGED_BY=compose
LIFECYCLE=long-lived
DATA_CLASS=confidential
DATA_LIFECYCLE=persistent
PROJECT_ID=project-123
DEPLOYMENT_ID=deployment-456
STACK=labels-test
ENV

cat >"$temp_dir/compose.yml" <<'YAML'
name: ${STACK}
services:
  db:
    image: postgres:17-alpine
    volumes:
      - db_data:/var/lib/postgresql/data
    labels:
      solutions.etal.service: db
      solutions.etal.service_tier: persistence
  sender:
    image: alpine:3.22
    profiles: [batch]
    labels:
      solutions.etal.service: worker
      solutions.etal.service_lifecycle: job
      solutions.etal.data_class: public
volumes:
  db_data:
YAML

"$root/pm-compose-labels" \
    --env-file "$temp_dir/.env.generated" \
    --project-directory "$temp_dir" \
    --compose-file "$temp_dir/compose.yml" \
    --output "$temp_dir/labels.yml" >/dev/null

model="$(docker compose \
    --env-file "$temp_dir/.env.generated" \
    -f "$temp_dir/compose.yml" \
    -f "$temp_dir/labels.yml" \
    --profile '*' config --format json)"

[[ "$(jq '.services | length' <<<"$model")" == 2 ]]
[[ "$(jq -r '.services.sender.labels["solutions.etal.service_lifecycle"]' <<<"$model")" == job ]]
[[ "$(jq -r '.services.sender.labels["solutions.etal.data_class"]' <<<"$model")" == public ]]
[[ "$(jq -r '.services.sender.labels["solutions.etal.service_tier"]' <<<"$model")" == internal ]]
[[ "$(jq -r '.services.db.labels["solutions.etal.service_tier"]' <<<"$model")" == persistence ]]
[[ "$(jq -r '.services.db.labels["solutions.etal.data_lifecycle"]' <<<"$model")" == persistent ]]
[[ "$(jq -r '[.services[].labels["solutions.etal.stack"]] | unique | .[]' <<<"$model")" == labels-test ]]

cat >"$temp_dir/bad-stack.yml" <<'YAML'
services:
  web:
    image: alpine:3.22
    labels:
      solutions.etal.stack: wrong-stack
YAML

if "$root/pm-compose-labels" \
    --env-file "$temp_dir/.env.generated" \
    --compose-file "$temp_dir/bad-stack.yml" \
    --output "$temp_dir/bad-stack-labels.yml" \
    >"$temp_dir/bad-stack.out" 2>"$temp_dir/bad-stack.err"; then
    printf 'Expected an explicit stack mismatch to fail.\n' >&2
    exit 1
fi
grep -Fq 'must match active STACK labels-test' "$temp_dir/bad-stack.err"
[[ ! -e "$temp_dir/bad-stack-labels.yml" ]]

grep -v '^DATA_LIFECYCLE=' "$temp_dir/.env.generated" \
    >"$temp_dir/missing.env.generated"
if "$root/pm-compose-labels" \
    --env-file "$temp_dir/missing.env.generated" \
    --compose-file "$temp_dir/compose.yml" \
    --output "$temp_dir/missing-labels.yml" \
    >"$temp_dir/missing.out" 2>"$temp_dir/missing.err"; then
    printf 'Expected a missing resolved input to fail.\n' >&2
    exit 1
fi
grep -Fq 'DATA_LIFECYCLE is missing or empty' "$temp_dir/missing.err"

cat >"$temp_dir/shared.yml" <<'YAML'
services:
  first:
    image: alpine:3.22
    volumes:
      - shared_data:/one
  second:
    image: alpine:3.22
    volumes:
      - shared_data:/two
    labels:
      solutions.etal.data_class: public
volumes:
  shared_data:
YAML

if "$root/pm-compose-labels" \
    --env-file "$temp_dir/.env.generated" \
    --compose-file "$temp_dir/shared.yml" \
    --output "$temp_dir/shared-labels.yml" \
    >"$temp_dir/shared.out" 2>"$temp_dir/shared.err"; then
    printf 'Expected conflicting shared-volume metadata to fail.\n' >&2
    exit 1
fi
grep -Fq 'named volume shared_data' "$temp_dir/shared.err"
grep -Fq 'conflicting data_class=confidential,public' "$temp_dir/shared.err"

if grep -Fq 'pm_setup_prepare_compose_labels' "$root/pm-setup"; then
    printf 'pm-setup must not run the Compose-label preflight.\n' >&2
    exit 1
fi

printf 'PASS: Compose labels compile, preserve explicit values, and validate all profiles.\n'

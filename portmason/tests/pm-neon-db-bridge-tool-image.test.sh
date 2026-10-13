#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
bridge="$source_dir/pm-db-bridge-postgres-neon"

bash -n "$bridge"

grep -Eq '^: "\$\{POSTGRES_TOOL_IMAGE:=postgres:17-alpine\}"' "$bridge"
grep -Eq '^export POSTGRES_TOOL_IMAGE DB_CONNECT_TIMEOUT_SECONDS$' "$bridge"
grep -Eq '^[[:space:]]+"image=\$POSTGRES_TOOL_IMAGE"$' "$bridge"
grep -Eq '^[[:space:]]+"\$POSTGRES_TOOL_IMAGE" \\' "$bridge"

docker_runs="$(grep -c '^[[:space:]]*docker run ' "$bridge")"
image_args="$(grep -c '^[[:space:]]*"\$POSTGRES_TOOL_IMAGE" \\' "$bridge")"
[[ "$docker_runs" -eq 2 ]]
[[ "$image_args" -eq 2 ]]

printf 'Portmason Neon database bridge tool-image contract test passed.\n'

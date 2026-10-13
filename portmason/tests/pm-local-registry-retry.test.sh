#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
deploy="$root/pm-deploy-local"

bash -n "$deploy"
grep -Fq 'PM_REGISTRY_PULL_ATTEMPTS:-3' "$deploy"
grep -Fq 'transient container registry failure; retrying Compose deployment' "$deploy"
grep -Eq '\(unexpected \)\?EOF\|TLS handshake timeout\|connection reset' "$deploy"
grep -Fq 'pm_local_compose_up -d --build --remove-orphans' "$deploy"

echo "PASS: local registry retry contract"

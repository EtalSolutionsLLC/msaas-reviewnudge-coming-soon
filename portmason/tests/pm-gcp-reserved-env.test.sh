#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

cat > "$tmp/pm-helpers" <<'HELPERS'
log() { :; }
die() { return "${2:-1}"; }
HELPERS

PORTMASON_SHARE="$tmp"
source "$root/pm-deploy-gcp"

env_file="$tmp/runtime.yaml"
cat > "$env_file" <<'ENV'
PORT: "3080"
K_SERVICE: "stale"
K_REVISION: "stale"
K_CONFIGURATION: "stale"
NODE_ENV: "production"
APP_HOST: "reviewnudge.etal.solutions"
ENV

pm_gcp_filter_reserved_env_file "$env_file"

! grep -Eq '^(PORT|K_SERVICE|K_REVISION|K_CONFIGURATION):' "$env_file"
grep -Fq 'NODE_ENV: "production"' "$env_file"
grep -Fq 'APP_HOST: "reviewnudge.etal.solutions"' "$env_file"

export STACK=reviewnudge-prd
export DEPLOYMENT_ID=reviewnudge-prd-1778712786
export PROJECT_SERVICES='[{"service":"inbound-worker","role":"worker","queue_consume":"inbound-events","queue_path":"/api/inbound-events"}]'
pm_gcp_append_queue_env "$env_file"
grep -Fq 'PM_QUEUE_PROVIDER: "pubsub"' "$env_file"
grep -Fq 'PM_QUEUE_PROJECT: "reviewnudge-prd-1778712786"' "$env_file"
grep -Fq 'PM_QUEUE_TOPIC: "reviewnudge-prd-inbound-worker"' "$env_file"
grep -Fq 'PM_QUEUE_PUSH_PATH: "/api/inbound-events"' "$env_file"
! grep -Eq '^PM_QUEUE_[A-Z_]+=' "$env_file"

dotenv_file="$tmp/runtime.env"
printf '%s\n' 'NODE_ENV=production' > "$dotenv_file"
pm_gcp_append_queue_env "$dotenv_file"
grep -Fq 'PM_QUEUE_PROVIDER=pubsub' "$dotenv_file"
! grep -Eq '^PM_QUEUE_[A-Z_]+:' "$dotenv_file"

echo "PASS: GCP reserved environment variables are filtered"

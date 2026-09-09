#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
log() { :; }
die() { return "${2:-1}"; }
have() { command -v "$1" >/dev/null 2>&1; }
env_init_set() { printf -v "$1" '%s' "${2-}"; export "$1"; }
export PORTMASON_SHARE="$root"
source "$root/pm-helpers-db"

PM_COMPOSE_MODEL_JSON='{
  "services": {
    "queue": {
      "image": "rabbitmq:4-alpine"
    },
    "web": {
      "image": "app:test",
      "depends_on": {"queue": {"condition": "service_healthy"}}
    },
    "worker": {
      "image": "app:test",
      "command": ["node", "src/worker.js", "consume"],
      "depends_on": {"queue": {"condition": "service_healthy"}}
    },
    "scheduler": {
      "image": "app:test",
      "command": ["src/scheduler-entrypoint.sh"],
      "environment": {
        "TZ": "America/Los_Angeles",
        "SCHEDULE_OUTBOUND_COMMUNICATIONS": "0 2 * * *|node src/scheduler-publisher.js outbound-communications",
        "SCHEDULE_EXTERNAL_SYNC": "0 * * * *|node src/scheduler-publisher.js external-sync",
        "SCHEDULE_HOUSEKEEPING": "30 3 * * *|node src/scheduler-publisher.js housekeeping"
      },
      "depends_on": {"queue": {"condition": "service_healthy"}}
    }
  }
}'
PROJECT_SERVICES='[]'
export PM_COMPOSE_MODEL_JSON PROJECT_SERVICES

pm_compose_load_model

[[ "$(jq -r '.[] | select(.service == "queue") | .role' <<<"$PROJECT_SERVICES")" == "queue" ]]
[[ "$(jq -r '.[] | select(.service == "queue") | .queue_engine' <<<"$PROJECT_SERVICES")" == "rabbitmq" ]]
[[ "$(jq -r '.[] | select(.service == "worker") | .queue_consume' <<<"$PROJECT_SERVICES")" == "queue" ]]
[[ "$(jq -r '.[] | select(.service == "scheduler") | .queue_publish' <<<"$PROJECT_SERVICES")" == "queue" ]]
[[ "$(jq -r '.[] | select(.service == "scheduler") | .schedules | length' <<<"$PROJECT_SERVICES")" == "3" ]]
[[ "$(jq -r '.[] | select(.service == "scheduler") | .schedule_timezone' <<<"$PROJECT_SERVICES")" == "America/Los_Angeles" ]]

printf 'PASS: Compose capabilities are inferred without Portmason labels\n'

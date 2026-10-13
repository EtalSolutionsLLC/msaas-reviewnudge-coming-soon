#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
calls_file="$(mktemp)"
trap 'rm -f -- "$calls_file"' EXIT

source "$root/pm-deploy-gcp"

export STACK=reviewnudge-prd
export DEPLOYMENT_ID=reviewnudge-prd-1778712786
export REGION=us-central1
export PROJECT_SERVICES='[
  {
    "service": "worker",
    "role": "worker",
    "queue_consume": "queue"
  },
  {
    "service": "scheduler",
    "role": "scheduler",
    "schedule_timezone": "America/Los_Angeles",
    "schedules": [
      {
        "name": "outbound-communications",
        "cron": "0 2 * * *",
        "command": "node src/scheduler-publisher.js outbound-communications"
      },
      {
        "name": "external-sync",
        "cron": "0 * * * *",
        "command": "node src/scheduler-publisher.js external-sync"
      },
      {
        "name": "housekeeping",
        "cron": "30 3 * * *",
        "command": "node src/scheduler-publisher.js housekeeping"
      }
    ]
  }
]'

gcloud() {
    printf '%s\n' "$*" >>"$calls_file"

    if [[ "$1" == "projects" && "$2" == "describe" ]]; then
        printf '123456789\n'
        return 0
    fi

    if [[ "$1" == "scheduler" && "$2" == "jobs" && "$3" == "describe" ]]; then
        [[ "$4" != "reviewnudge-prd-scheduler-outbound-communications" ]]
        return
    fi

    if [[ "$1" == "scheduler" && "$2" == "jobs" && "$3" == "list" ]]; then
        printf '%s\n' \
            reviewnudge-prd-scheduler-lifecycle \
            reviewnudge-prd-scheduler-external-sync \
            reviewnudge-prd-scheduler-housekeeping \
            unrelated-scheduler
        return 0
    fi

    return 0
}

ensure_compose_schedules

grep -Fq \
    'scheduler jobs create pubsub reviewnudge-prd-scheduler-outbound-communications' \
    "$calls_file"
grep -Fq \
    'scheduler jobs delete reviewnudge-prd-scheduler-lifecycle' \
    "$calls_file"

if grep -Fq 'scheduler jobs delete reviewnudge-prd-scheduler-external-sync' "$calls_file" \
    || grep -Fq 'scheduler jobs delete reviewnudge-prd-scheduler-housekeeping' "$calls_file" \
    || grep -Fq 'scheduler jobs delete unrelated-scheduler' "$calls_file"; then
    printf 'FAIL: reconciliation deleted a desired or unmanaged scheduler\n' >&2
    exit 1
fi

printf 'PASS: Compose schedule reconciliation replaces only obsolete managed schedulers\n'

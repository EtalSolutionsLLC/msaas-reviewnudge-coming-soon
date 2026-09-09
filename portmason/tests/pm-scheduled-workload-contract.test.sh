#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

bash -n "$root/pm-helpers-db" "$root/pm-deploy-gcp" "$root/pm-provision-gcp"

grep -Fq 'solutions.etal.run.command' "$root/pm-helpers-db"
grep -Fq 'solutions.etal.run.args' "$root/pm-helpers-db"
grep -Fq 'solutions.etal.queue.publish' "$root/pm-helpers-db"
grep -Fq 'solutions.etal.queue.consume' "$root/pm-helpers-db"
grep -Fq 'solutions.etal.queue.delivery' "$root/pm-helpers-db"
grep -Fq 'solutions.etal.schedule.cron' "$root/pm-helpers-db"
grep -Fq 'solutions.etal.schedule.timezone' "$root/pm-helpers-db"
grep -Fq '.role != "queue"' "$root/pm-helpers-db"
grep -Fq 'pm_compose_control_file' "$root/pm-helpers-db"
if grep -Fq 'canonical development Compose model' "$root/pm-helpers-db"; then
    echo "provider adapters must not merge a second Compose model" >&2
    exit 1
fi
grep -Fq 'service_command_args "$service" command_flags' "$root/pm-deploy-gcp"
grep -Fq 'access_flags=(--no-allow-unauthenticated --ingress internal)' "$root/pm-deploy-gcp"
grep -Fq 'PM_QUEUE_PROVIDER=pubsub' "$root/pm-deploy-gcp"
grep -Fq 'Pub/Sub push queue ready' "$root/pm-deploy-gcp"
grep -Fq 'Cloud Tasks scheduled queue ready' "$root/pm-deploy-gcp"
grep -Fq 'PM_SCHEDULED_WORK_PROVIDER=cloud-tasks' "$root/pm-deploy-gcp"
grep -Fq 'target=pubsub://${DEPLOYMENT_ID}/${topic}' "$root/pm-deploy-gcp"
if grep -Fq 'PM_SCHEDULED_WORK_TARGET_URL' "$root/pm-deploy-gcp"; then
    echo "Cloud Tasks scheduled delivery must funnel through Pub/Sub" >&2
    exit 1
fi
grep -Fq 'ensure_compose_schedules' "$root/pm-deploy-gcp"
grep -Fq 'Cloud Scheduler queue trigger ready' "$root/pm-deploy-gcp"
grep -Fq 'gcloud scheduler jobs create pubsub' "$root/pm-deploy-gcp"
grep -Fq 'deleting obsolete Compose Cloud Scheduler queue trigger' "$root/pm-deploy-gcp"
grep -Fq 'pubsub.googleapis.com' "$root/pm-provision-gcp"
grep -Fq 'cloudtasks.googleapis.com' "$root/pm-provision-gcp"
grep -Fq 'cloudscheduler.googleapis.com' "$root/pm-provision-gcp"
grep -Fq 'Cloud Run job schedule ready' "$root/pm-deploy-gcp"
grep -Fq 'pm_gcp_cleanup_obsolete_legacy_jobs_schedule' "$root/pm-deploy-gcp"
grep -Fq 'deleting obsolete legacy Cloud Scheduler job' "$root/pm-deploy-gcp"
grep -Fq 'deleting obsolete legacy Cloud Run job' "$root/pm-deploy-gcp"
grep -Fq 'removing obsolete Cloud Run job after worker service migration' "$root/pm-deploy-gcp"
if grep -Fq 'SCHED_NAME' "$root/pm-provision-gcp"; then
    echo "legacy SCHED_NAME must not gate Compose-managed schedules" >&2
    exit 1
fi
if grep -Fq 'ensure_scheduler' "$root/pm-provision-gcp"; then
    echo "legacy scheduler provisioning must not coexist with the Compose contract" >&2
    exit 1
fi
if grep -Fq 'jobs|worker)' "$root/pm-deploy-gcp"; then
    echo "continuous workers must not be deployed as finite Cloud Run jobs" >&2
    exit 1
fi
if grep -Eq '\[\[ -n "\$(first|rest|run_args)" \]\] &&' "$root/pm-deploy-gcp"; then
    echo "optional command metadata must not return a false function status" >&2
    exit 1
fi

echo "PASS: scheduled workload contract"

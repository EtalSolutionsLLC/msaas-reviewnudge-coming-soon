#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
bash -n "$root/pm-deploy-gcp"
grep -Fq 'pm_gcp_append_scheduled_work_env "${!out_var}" "$service"' "$root/pm-deploy-gcp"
grep -Fq 'PM_SCHEDULED_WORK_PROVIDER: "cloud-tasks"' "$root/pm-deploy-gcp"
grep -Fq 'verifying runtime build inputs' "$root/pm-deploy-gcp"
if grep -Fq -- '--update-env-vars "$env_values"' "$root/pm-deploy-gcp"; then
  echo 'scheduled-work config must not create a second Cloud Run revision' >&2
  exit 1
fi
echo 'PASS: Cloud Run scheduled-work config is included in the initial revision'

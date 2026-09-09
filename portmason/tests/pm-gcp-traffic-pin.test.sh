#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM
trace="$temp_dir/gcloud.trace"
log_file="$temp_dir/log.txt"

printf '#!/usr/bin/env bash\n:\n' > "$temp_dir/pm-helpers"
# Disable the deployer entrypoint; the test invokes the real deploy function.
sed '$d' "$source_dir/pm-deploy-gcp" > "$temp_dir/pm-deploy-gcp"
export PORTMASON_SHARE="$temp_dir"
. "$temp_dir/pm-deploy-gcp"

resource_name() { printf -v "$1" 'stack-%s' "$2"; }
runtime_service_account() { printf -v "$1" '%s@project.iam.gserviceaccount.com' "$2"; }
write_env_file_for_service_compat() { local out_var="$1" file="$temp_dir/service.env"; : >"$file"; printf -v "$out_var" '%s' "$file"; }
secret_args_for_service_compat() { :; }
service_run_once_args() { :; }
pm_gcp_cloud_sql_connections_csv() { printf -v "$1" '%s' ""; }
env_init_set() { printf -v "$1" '%s' "$2"; }
log() { printf '%s\n' "$*" >>"$log_file"; }
log_cmd() { :; }
die() { return "${2:-1}"; }
sleep() { :; }

gcloud() {
    printf '%q ' "$@" >>"$trace"; printf '\n' >>"$trace"

    if [[ "$1 $2" == "run deploy" ]]; then
        MOCK_DEPLOY_CALLED=true
        return 0
    fi
    if [[ "$1 $2 $3" == "run services describe" ]]; then
        if [[ "$*" == *"spec.traffic.revisionName"* ]]; then
            printf '%s\n' "${MOCK_PINNED_REVISION:-}"
        elif [[ "$*" == *"status.latestCreatedRevisionName"* ]]; then
            if [[ "${MOCK_DEPLOY_CALLED:-false}" == true ]]; then
                printf '%s\n' "${MOCK_STAGED_REVISION:-stack-web-00042}"
            else
                printf '%s\n' "${MOCK_PREVIOUS_REVISION:-stack-web-00040}"
            fi
        else
            printf 'https://service.run.app\n'
        fi
        return 0
    fi
    if [[ "$1 $2 $3" == "run revisions describe" ]]; then
        printf '%s\n' "${MOCK_STAGED_READY:-True}"
    fi
}

export DEPLOYMENT_ID=project REGION=us-central1 PORT=3080
MOCK_DEPLOY_CALLED=false
MOCK_PINNED_REVISION=""
deploy_cloud_run_service web web image:test
grep -Fq -- 'run deploy' "$trace"
! grep -Fq -- '--no-traffic' "$trace"

: >"$trace"
MOCK_DEPLOY_CALLED=false
MOCK_PINNED_REVISION=stack-web-00042
MOCK_PREVIOUS_REVISION=stack-web-00040
MOCK_STAGED_REVISION=stack-web-00042
MOCK_STAGED_READY=True
deploy_cloud_run_service web web image:test
grep -Fq -- 'run deploy' "$trace"
grep -Fq -- '--no-traffic' "$trace"
grep -Fq -- '--async' "$trace"
grep -Fq 'staged Cloud Run revision is Ready; traffic remains pinned' "$log_file"
printf 'Portmason Cloud Run pinned-traffic deployment tests passed.\n'

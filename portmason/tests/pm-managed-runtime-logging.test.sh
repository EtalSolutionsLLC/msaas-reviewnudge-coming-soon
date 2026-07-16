#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
helpers="$source_dir/pm-helpers"

bash -n "$helpers"

routing_text="$(
    sed -n '/^pm_log_value_is_true() {/,/^# Internal: should we emit/p' "$helpers" \
        | sed '$d'
)"

[[ -n "$routing_text" ]] || {
    printf 'Managed-runtime logging functions were not found.\n' >&2
    exit 1
}

eval "$routing_text"

runtime_vars=(
    PM_LOG_RUNTIME_OVERRIDE
    GITHUB_ACTIONS CI GITLAB_CI TF_BUILD BUILDKITE CIRCLECI JENKINS_URL
    TEAMCITY_VERSION BITBUCKET_BUILD_NUMBER CODEBUILD_BUILD_ID
    K_SERVICE K_REVISION K_CONFIGURATION CLOUD_RUN_JOB CLOUD_RUN_EXECUTION
    GAE_SERVICE
    AWS_EXECUTION_ENV AWS_LAMBDA_FUNCTION_NAME AWS_LAMBDA_RUNTIME_API
    ECS_CONTAINER_METADATA_URI ECS_CONTAINER_METADATA_URI_V4 AWS_BATCH_JOB_ID
    WEBSITE_INSTANCE_ID WEBSITE_SITE_NAME CONTAINER_APP_NAME
    CONTAINER_APP_REVISION FUNCTIONS_WORKER_RUNTIME
    KUBERNETES_SERVICE_HOST
)

clear_runtime_vars() {
    unset "${runtime_vars[@]}"
}

assert_runtime() {
    local expected="${1:?expected runtime required}"
    shift
    local assignment actual

    clear_runtime_vars
    for assignment in "$@"; do
        export "$assignment"
    done

    pm_log_detect_runtime actual
    [[ "$actual" == "$expected" ]] || {
        printf 'Expected runtime %s, got %s for %s\n' \
            "$expected" "$actual" "$*" >&2
        exit 1
    }
}

assert_runtime github-actions GITHUB_ACTIONS=true
assert_runtime gcp K_SERVICE=reviewnudge
assert_runtime aws AWS_LAMBDA_FUNCTION_NAME=reviewnudge-handler
assert_runtime azure WEBSITE_INSTANCE_ID=azure-instance
assert_runtime kubernetes KUBERNETES_SERVICE_HOST=10.0.0.1
assert_runtime ci CI=true
assert_runtime aws PM_LOG_RUNTIME_OVERRIDE=aws
assert_runtime local

clear_runtime_vars
export AWS_EXECUTION_ENV=AWS_Lambda_nodejs22.x
export PM_NO_REDIRECT=1
export IN_CONTAINER=false
unset LOG_FORMAT PM_LOG_RUNTIME PM_LOG_SINK
setup_logging 2>/dev/null

[[ "$PM_LOG_RUNTIME" == "aws" ]]
[[ "$PM_LOG_SINK" == "platform" ]]
[[ "$LOG_FORMAT" == "json" ]]

clear_runtime_vars
export GITHUB_ACTIONS=true
export PM_NO_REDIRECT=1
export IN_CONTAINER=false
unset LOG_FORMAT PM_LOG_RUNTIME PM_LOG_SINK
setup_logging 2>/dev/null

[[ "$PM_LOG_RUNTIME" == "github-actions" ]]
[[ "$PM_LOG_SINK" == "platform" ]]
[[ "$LOG_FORMAT" == "text" ]]

local_log_dir="$(mktemp -d)"
cleanup() {
    case "$local_log_dir" in
        /tmp/tmp.*) rm -rf -- "$local_log_dir" ;;
        *)
            printf 'Refusing to remove unexpected test path: %s\n' \
                "$local_log_dir" >&2
            ;;
    esac
}
trap cleanup EXIT INT TERM

clear_runtime_vars
export PM_LOG_RUNTIME_OVERRIDE=local
export PM_LOG_LOCAL_TEE=1
export IN_CONTAINER=false
export LOG_DIR="$local_log_dir"
export LOG_FILE_CONFIGURE="$local_log_dir/local.log"
unset PM_NO_REDIRECT PM_FORCE_REDIRECT LOG_FORMAT PM_LOG_RUNTIME PM_LOG_SINK

local_console_output="$(
    (
        setup_logging
        printf 'local stdout marker\n'
        printf 'local stderr marker\n' >&2
        exec 1>&- 2>&-
        wait
    ) 2>&1
)"

[[ "$local_console_output" == *'local stdout marker'* ]]
[[ "$local_console_output" == *'local stderr marker'* ]]
grep -Fq 'local stdout marker' "$local_log_dir/local.log"
grep -Fq 'local stderr marker' "$local_log_dir/local.log"

extract_simple_function() {
    local function_name="${1:?function name required}"
    awk -v start="${function_name}() {" '
        $0 == start { capture=1 }
        capture { print }
        capture && $0 == "}" { exit }
    ' "$helpers"
}

eval "$(extract_simple_function bail)"
eval "$(extract_simple_function die)"
eval "$(extract_simple_function fatal)"
eval "$(extract_simple_function fatal_error)"

log() {
    local severity="${1:-INFO}"
    local message="${2:-}"
    shift 2 || true
    printf '%s|%s|%s\n' "$severity" "$message" "$*" >&2
}

error() { log ERROR "$@"; }

assert_terminal_event() {
    local expected_rc="${1:?expected return code required}"
    local expected_event="${2:?expected event required}"
    shift 2
    local output rc

    set +e
    output="$( ( "$@" ) 2>&1 )"
    rc=$?
    set -e

    [[ "$rc" -eq "$expected_rc" ]] || {
        printf 'Expected exit %s, got %s from %s\n' \
            "$expected_rc" "$rc" "$*" >&2
        exit 1
    }
    [[ "$output" == *"$expected_event"* ]] || {
        printf 'Missing terminal event %s in:\n%s\n' \
            "$expected_event" "$output" >&2
        exit 1
    }
}

assert_terminal_event 7 'CRITICAL|deployment failed|exit_code=7' \
    die 'deployment failed' 7
assert_terminal_event 8 'ERROR|configuration failed|exit_code=8' \
    fatal_error 'configuration failed' 8
assert_terminal_event 9 'CRITICAL|Process terminated|exit_code=9' \
    fatal 9
assert_terminal_event 10 'ERROR|validation failed|exit_code=10' \
    bail 'validation failed' 10

eval "$(extract_simple_function should_log)"
export LOG_LEVEL=ERROR
should_log CRITICAL
if should_log WARNING; then
    printf 'WARNING unexpectedly passed an ERROR log threshold.\n' >&2
    exit 1
fi
unset LOG_LEVEL

function_text="$(awk '
    /^log\(\) \{/ {capture=1}
    capture {print}
    capture && /^}/ {exit}
' "$helpers")"

should_log() { return 0; }
pm_error_record() { return 0; }
log_callsite() { printf 'pm-setup\tmain\n'; }
export PM_ENTRY_SCRIPT=pm-setup
eval "$function_text"

export LOG_FORMAT=json
export PM_LOG_RUNTIME=aws
export AWS_LAMBDA_FUNCTION_NAME=reviewnudge-handler
export AWS_LAMBDA_FUNCTION_VERSION=42
export PM_DEPLOYMENT_ID=deployment-123

json_line="$(log INFO 'cloud event' 2>&1)"
[[ "$json_line" == *'"runtime":"aws"'* ]]
[[ "$json_line" == *'"cloud_provider":"aws"'* ]]
[[ "$json_line" == *'"service":"reviewnudge-handler"'* ]]
[[ "$json_line" == *'"revision":"42"'* ]]
[[ "$json_line" == *'"deployment_id":"deployment-123"'* ]]

printf 'Portmason managed-runtime logging tests passed.\n'

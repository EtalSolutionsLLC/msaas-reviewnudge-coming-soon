#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM
log_file="$temp_dir/log.txt"

# Syntax and release-marker checks.
bash -n "$source_dir/pm-setup"
grep -Fq 'log INFO "application ready" "APP_URL=${APP_URL}"' "$source_dir/pm-setup"
grep -Fq 'warn "application URL unavailable" "APP_URL=<unset>"' "$source_dir/pm-setup"

# Load only the completion function so the test remains independent from the
# full pm-setup bootstrap and can verify the operator-facing log contract.
function_text="$(awk '
  /^pm_setup_log_completion\(\)/ {capture=1}
  capture {print}
  capture && /^}/ {exit}
' "$source_dir/pm-setup")"

[[ -n "$function_text" ]] || {
  printf 'pm_setup_log_completion was not found.\n' >&2
  exit 1
}

log() { printf 'LOG|%s\n' "$*" >>"$log_file"; }
warn() { printf 'WARN|%s\n' "$*" >>"$log_file"; }
ensure_app_url() {
  if [[ -z "${APP_URL:-}" && -n "${APP_HOST:-}" ]]; then
    APP_URL="http://${APP_HOST}"
    export APP_URL
  fi
}

eval "$function_text"

export DEPLOY_ENV=dev STACK=reviewnudge-dev APP_URL=https://reviewnudge.example.test
pm_setup_log_completion
[[ "$(tail -n 1 "$log_file")" == *'application ready APP_URL=https://reviewnudge.example.test' ]]

: >"$log_file"
unset APP_URL
export APP_HOST=reviewnudge-dev.localtest.me
pm_setup_log_completion
[[ "$(tail -n 1 "$log_file")" == *'application ready APP_URL=http://reviewnudge-dev.localtest.me' ]]

: >"$log_file"
unset APP_URL APP_HOST
pm_setup_log_completion
[[ "$(tail -n 1 "$log_file")" == *'application URL unavailable APP_URL=<unset>' ]]

printf 'Portmason APP_URL completion-log tests passed.\n'

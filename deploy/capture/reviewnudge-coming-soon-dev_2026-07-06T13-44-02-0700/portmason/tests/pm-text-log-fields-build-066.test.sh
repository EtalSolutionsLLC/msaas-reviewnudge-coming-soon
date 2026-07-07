#!/usr/bin/env bash
set -euo pipefail

source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_dir="$(mktemp -d)"
trap 'rm -rf -- "$temp_dir"' EXIT INT TERM
log_file="$temp_dir/log.txt"

bash -n "$source_dir/pm-helpers"
bash -n "$source_dir/pm-setup"

function_text="$(awk '
  /^log\(\) \{/ {capture=1}
  capture {print}
  capture && /^}/ {exit}
' "$source_dir/pm-helpers")"

[[ -n "$function_text" ]] || {
  printf 'log function was not found.\n' >&2
  exit 1
}

should_log() { return 0; }
log_callsite() { printf 'pm-setup\tpm_setup_log_completion\n'; }
export PM_ENTRY_SCRIPT=pm-setup

eval "$function_text"

export LOG_FORMAT=text
log INFO "application ready" \
  "APP_URL=http://reviewnudge-dev.localtest.me" \
  "stack=reviewnudge-dev" 2>"$log_file"

text_line="$(tail -n 1 "$log_file")"
[[ "$text_line" == *'application ready APP_URL=http://reviewnudge-dev.localtest.me stack=reviewnudge-dev' ]] || {
  printf 'Text log omitted structured fields:\n%s\n' "$text_line" >&2
  exit 1
}

: >"$log_file"
export LOG_FORMAT=json
log INFO "application ready" \
  "APP_URL=https://reviewnudge.example.test" \
  "stack=reviewnudge-prd" 2>"$log_file"

json_line="$(tail -n 1 "$log_file")"
[[ "$json_line" == *'"message":"application ready"'* ]]
[[ "$json_line" == *'"script":"pm-setup"'* ]]
[[ "$json_line" == *'"APP_URL":"https://reviewnudge.example.test"'* ]]
[[ "$json_line" == *'"stack":"reviewnudge-prd"'* ]]

: >"$log_file"
export LOG_FORMAT=text
log "single-argument message" 2>"$log_file"
[[ "$(tail -n 1 "$log_file")" == *'] single-argument message' ]]

grep -Fq 'log INFO "application ready" "APP_URL=${APP_URL}"' "$source_dir/pm-setup"

printf 'Portmason structured text-log tests passed.\n'

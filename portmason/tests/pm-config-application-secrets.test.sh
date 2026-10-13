#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
declare -a registrations=()

pm_config_register() {
    registrations+=("$1|$2|$3|$4|$5")
}

# shellcheck disable=SC1091
. "$root/pm-config-application"
pm_config_application

contract="$(printf '%s\n' "${registrations[@]}")"
grep -Fxq 'PAYMENTS_SECRET_KEY|secret|application,web,app,jobs,worker|PAYMENTS_SECRET_KEY|optional' <<<"$contract"
grep -Fxq 'PAYMENTS_WEBHOOK_SECRET|secret|application,web,app,jobs,worker|PAYMENTS_WEBHOOK_SECRET|optional' <<<"$contract"

printf 'PASS: application payment secrets are registered\n'

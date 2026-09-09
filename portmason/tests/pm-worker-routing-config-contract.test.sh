#!/usr/bin/env bash
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
core="$root/pm-config-core"

bash -n "$core"

grep -Eq "pm_config_register URI_SCHEME var 'routing,web,app,worker,jobs,proxy' URI_SCHEME optional" "$core"
grep -Eq "pm_config_register APP_HOST var 'routing,web,app,worker,jobs,proxy' APP_HOST optional" "$core"
grep -Eq "pm_config_register APP_URL var 'routing,web,app,worker,jobs,proxy' APP_URL optional" "$core"

printf 'Portmason worker routing configuration contract test passed.\n'

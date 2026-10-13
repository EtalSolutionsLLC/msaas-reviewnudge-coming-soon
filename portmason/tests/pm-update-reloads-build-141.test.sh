#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SETUP="${ROOT}/pm-setup"

bash -n "$SETUP"

grep -Fq 'PM_SETUP_UPDATE_REENTERED="${PM_SETUP_UPDATE_REENTERED:-0}"' "$SETUP"
grep -Fq 'export PM_SETUP_UPDATE_REENTERED=1' "$SETUP"
grep -Fq 'cd -- "${PM_SETUP_INVOKED_FROM}"' "$SETUP"
grep -Fq 'exec "${PORTMASON_SHARE}/pm-setup" "$@"' "$SETUP"

reload_line="$(grep -nF 'exec "${PORTMASON_SHARE}/pm-setup" "$@"' "$SETUP" | cut -d: -f1)"
helpers_line="$(grep -nF '. "${PORTMASON_SHARE}/pm-helpers" "$@"' "$SETUP" | head -n1 | cut -d: -f1)"

(( reload_line < helpers_line ))

printf 'PASS: pm-setup reloads after update before project bootstrap\n'

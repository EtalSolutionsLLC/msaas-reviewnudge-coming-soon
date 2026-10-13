#!/usr/bin/env bash
set -euo pipefail

cat > pm-log <<'PMLOG'
#!/usr/bin/env bash
set -euo pipefail

: "${PORTMASON_SHARE:=$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]:-${0:-}}")" \
  && pwd -P
)}"

. "${PORTMASON_SHARE}/pm-helpers"

if (( $# == 0 )); then
  log ""
elif (( $# == 1 )); then
  log "$1"
else
  level="$1"
  shift
  log "$level" "$*"
fi
PMLOG

chmod +x pm-log

cat > pm-log.js <<'NODE'
import { spawnSync } from "node:child_process";

function pmLogCommand() {
  if (process.env.PORTMASON_SHARE) {
    return `${process.env.PORTMASON_SHARE}/pm-log`;
  }

  return "pm-log";
}

export function log(
  levelOrMessage,
  maybeMessage,
) {
  const args =
    maybeMessage === undefined
      ? [String(levelOrMessage)]
      : [
          String(levelOrMessage),
          String(maybeMessage),
        ];

  const result =
    spawnSync(
      pmLogCommand(),
      args,
      {
        stdio: "inherit",
        env: process.env,
      },
    );

  if (result.error) {
    const fallbackLevel =
      maybeMessage === undefined
        ? "INFO"
        : String(levelOrMessage);

    const fallbackMessage =
      maybeMessage === undefined
        ? String(levelOrMessage)
        : String(maybeMessage);

    console.log(
      `[${fallbackLevel}] ${fallbackMessage}`,
    );
  }
}
NODE

cat > pm_log.py <<'PY'
import os
import subprocess


def _pm_log_command():
    portmason_share = os.environ.get("PORTMASON_SHARE")

    if portmason_share:
        return os.path.join(
            portmason_share,
            "pm-log",
        )

    return "pm-log"


def log(level_or_message, message=None):
    if message is None:
        args = [
            str(level_or_message),
        ]
    else:
        args = [
            str(level_or_message),
            str(message),
        ]

    try:
        subprocess.run(
            [
                _pm_log_command(),
                *args,
            ],
            check=False,
        )
    except Exception:
        if message is None:
            level = "INFO"
            text = str(level_or_message)
        else:
            level = str(level_or_message)
            text = str(message)

        print(
            f"[{level}] {text}"
        )
PY

echo "Installed:"
echo "  ./pm-log"
echo "  ./pm-log.js"
echo "  ./pm_log.py"
echo
echo "Smoke test:"
./pm-log INFO "pm-log wrapper installed"

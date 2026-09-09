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

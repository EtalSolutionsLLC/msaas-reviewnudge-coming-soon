#!/usr/bin/env python3
"""Supply an encrypted GCP environment file through memory only."""
import json
import os
import subprocess
import sys

args = sys.argv[1:]
fds = []
try:
    if args[:1] == ["--"]:
        args = args[1:]
    if not args or args[0] != "gcloud":
        raise RuntimeError("Expected a gcloud command")
    found = False
    for index, argument in enumerate(args):
        if argument != "--env-vars-file":
            continue
        if index + 1 >= len(args):
            raise RuntimeError("Missing environment file")
        result = subprocess.run(
            ["sops", "--decrypt", "--input-type", "json",
             "--output-type", "json", args[index + 1]],
            capture_output=True, text=True, timeout=60,
        )
        if result.returncode:
            raise RuntimeError("Environment decryption failed")
        fd = os.memfd_create("portmason-gcp-env", os.MFD_CLOEXEC)
        fds.append(fd)
        with os.fdopen(os.dup(fd), "w") as stream:
            stream.write(json.dumps(json.loads(result.stdout), indent=2) + "\n")
        args[index + 1] = f"/proc/{os.getpid()}/fd/{fd}"
        found = True
    if not found:
        raise RuntimeError("Expected --env-vars-file")
    raise SystemExit(subprocess.run(args).returncode)
except (OSError, RuntimeError, subprocess.SubprocessError):
    print("GCP encrypted environment handoff failed", file=sys.stderr)
    raise SystemExit(2)
finally:
    for fd in fds:
        os.close(fd)

#!/usr/bin/env python3
"""Decrypt Compose environment inputs using memory-backed files only."""
import json
import os
from pathlib import Path
import subprocess
import sys

fds = []

def memory_file(text):
    fd = os.memfd_create("portmason-environment", os.MFD_CLOEXEC)
    fds.append(fd)
    with os.fdopen(os.dup(fd), "w", encoding="utf-8") as stream:
        stream.write(text)
    return f"/proc/{os.getpid()}/fd/{fd}"

def decrypt(filename):
    result = subprocess.run(
        ["sops", "--decrypt", "--input-type", "dotenv",
         "--output-type", "dotenv", str(filename)],
        capture_output=True, text=True, timeout=60,
    )
    if result.returncode:
        raise RuntimeError(f"Cannot decrypt environment file: {filename}")
    return result.stdout

def protect_dollars(value):
    # The first Compose pass already interpolated these values.
    if isinstance(value, str):
        return value.replace("$", "$$")
    if isinstance(value, list):
        return [protect_dollars(item) for item in value]
    if isinstance(value, dict):
        return {key: protect_dollars(item) for key, item in value.items()}
    return value

def main():
    args = sys.argv[1:]
    if args[:1] == ["--"]:
        args = args[1:]

    initial, final = [], []
    project = Path.cwd()
    explicit_env = False
    i = 0
    paired = {
        "-f", "--file", "--project-directory", "-p", "--project-name",
        "--profile", "--env-file", "--ansi", "--parallel", "--progress",
    }
    switches = {"--compatibility", "--all-resources", "--dry-run"}

    while i < len(args) and args[i].startswith("-"):
        flag = args[i]
        if flag in switches:
            initial.append(flag)
            final.append(flag)
            i += 1
            continue
        if flag not in paired or i + 1 >= len(args):
            raise RuntimeError(f"Unsupported Compose global option: {flag}")
        value = args[i + 1]
        if flag == "--project-directory":
            project = Path(value).resolve()
        if flag == "--env-file":
            explicit_env = True
            requested_env = Path(value).resolve()
            generated_env = Path(str(requested_env) + ".generated")
            runtime_env = (
                generated_env
                if generated_env.is_file() and generated_env.stat().st_size
                else requested_env
            )
            value = memory_file(decrypt(runtime_env))
        initial.extend([flag, value])
        if flag not in {"-f", "--file"}:
            final.extend([flag, value])
        i += 2

    command = args[i:]
    if not command:
        raise RuntimeError("A Compose command is required")

    if not explicit_env:
        source = Path(os.environ.get("ENV_FILE", project / ".env"))
        generated = Path(str(source) + ".generated")
        source = generated if generated.is_file() and generated.stat().st_size else source
        env_path = memory_file(decrypt(source))
        initial.extend(["--env-file", env_path])
        final.extend(["--env-file", env_path])

    # Prevent final Compose from resolving relative paths against /proc.
    if "--project-directory" not in final:
        initial.extend(["--project-directory", str(project)])
        final.extend(["--project-directory", str(project)])

    if command[0] == "config" and "--variables" in command:
        return subprocess.run(
            ["docker", "compose", *initial, *command, "--no-env-resolution"]
        ).returncode

    uninterpolated = command[0] == "config" and "--no-interpolate" in command
    inspect = [
        "docker", "compose", *initial,
        "--profile", "*", "config", "--no-env-resolution", "--format", "json",
    ]
    if uninterpolated:
        inspect.append("--no-interpolate")
    result = subprocess.run(inspect, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError("Compose model inspection failed; diagnostic output withheld")
    model = json.loads(result.stdout)

    decrypted_paths = {}
    for service in model.get("services", {}).values():
        entries = service.get("env_file", [])
        if isinstance(entries, (str, dict)):
            entries = [entries]
        for index, entry in enumerate(entries):
            item = {"path": entry} if isinstance(entry, str) else dict(entry)
            path = Path(item["path"])
            if not path.is_absolute():
                path = project / path
            if not path.exists() and item.get("required", True) is False:
                continue
            identity = str(path.resolve())
            if identity not in decrypted_paths:
                decrypted_paths[identity] = memory_file(decrypt(path))
            item["path"] = decrypted_paths[identity]
            entries[index] = item
        if entries:
            service["env_file"] = entries

    if not uninterpolated:
        model = protect_dollars(model)
    model_path = memory_file(json.dumps(model))
    return subprocess.run(
        ["docker", "compose", *final, "-f", model_path, *command]
    ).returncode

try:
    raise SystemExit(main())
except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
    # Do not print captured subprocess output or decrypted configuration.
    detail = str(error) if isinstance(error, RuntimeError) else "internal handoff error"
    print(f"Portmason Compose handoff failed: {detail}", file=sys.stderr)
    raise SystemExit(2)
finally:
    for fd in fds:
        os.close(fd)

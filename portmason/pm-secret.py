#!/usr/bin/env python3
"""Provider-neutral secret routing for Portmason."""

from __future__ import annotations

import argparse
import ctypes
import importlib.util
import os
import pathlib
import re
import resource
import sys
from types import ModuleType

PROVIDER_RE = re.compile(r"^[a-z][a-z0-9-]*$")
ENV_NAME_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")


def harden_process() -> None:
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    try:
        libc = ctypes.CDLL(None)
        libc.prctl(4, 0, 0, 0, 0)  # PR_SET_DUMPABLE
    except (AttributeError, OSError):
        pass


def wipe(value: bytearray) -> None:
    for index in range(len(value)):
        value[index] = 0


def split_secret_path(secret_path: str) -> tuple[str, str]:
    if ":" not in secret_path:
        raise ValueError("secret path must use provider:secret")
    provider, secret_ref = secret_path.split(":", 1)
    if not PROVIDER_RE.fullmatch(provider):
        raise ValueError("secret path contains an invalid provider")
    if not secret_ref:
        raise ValueError("secret path contains an empty secret reference")
    return provider, secret_ref


def load_provider(secret_path: str) -> tuple[ModuleType, str]:
    provider, secret_ref = split_secret_path(secret_path)
    share = pathlib.Path(
        os.environ.get("PORTMASON_SHARE", pathlib.Path(__file__).resolve().parent)
    )
    provider_file = share / f"pm-secret-provider-{provider}.py"
    if not provider_file.is_file():
        raise RuntimeError(f"secret provider module is unavailable: {provider}")
    module_name = f"portmason_secret_provider_{provider.replace('-', '_')}"
    spec = importlib.util.spec_from_file_location(module_name, provider_file)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load secret provider module: {provider}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module, secret_ref


def provider_function(secret_path: str, function_name: str):
    module, secret_ref = load_provider(secret_path)
    function = getattr(module, function_name, None)
    if not callable(function):
        provider, _ = split_secret_path(secret_path)
        raise RuntimeError(
            f"secret provider {provider} does not implement {function_name}"
        )
    return function, secret_ref

def get_secret(secret_path: str) -> bytearray:
    function, secret_ref = provider_function(secret_path, "get_secret")
    result = function(secret_ref)
    value = result if isinstance(result, bytearray) else bytearray(result)
    if not value:
        raise RuntimeError("secret provider returned an empty value")
    return value


def set_secret(secret_path: str, value: bytearray) -> None:
    if not value:
        raise ValueError("refusing to store an empty secret")
    function, secret_ref = provider_function(secret_path, "set_secret")
    function(secret_ref, value)



def read_stdin() -> bytearray:
    value = bytearray()
    while True:
        chunk = os.read(0, 4096)
        if not chunk:
            return value
        value.extend(chunk)


def write_stdout(value: bytearray) -> None:
    view = memoryview(value)
    while view:
        written = os.write(1, view)
        view = view[written:]


def run_get(secret_path: str) -> None:
    function, secret_ref = provider_function(secret_path, "get_secret")
    secret = bytearray()
    try:
        result = function(secret_ref)
        secret = result if isinstance(result, bytearray) else bytearray(result)
        if not secret:
            raise RuntimeError("secret provider returned an empty value")
        write_stdout(secret)
    finally:
        wipe(secret)


def run_set(secret_path: str) -> None:
    function, secret_ref = provider_function(secret_path, "set_secret")
    secret = read_stdin()
    try:
        if not secret:
            raise ValueError("refusing to store an empty secret")
        function(secret_ref, secret)
    finally:
        wipe(secret)


def run_check(secret_path: str, operation: str) -> None:
    provider_function(secret_path, f"{operation}_secret")


def run_with_secrets(bindings: list[str], command: list[str]) -> None:
    if command and command[0] == "--":
        command = command[1:]
    if not command:
        raise ValueError("run-with-secrets requires a command")

    environment = os.environ.copy()
    secrets: list[bytearray] = []
    try:
        if "--no-interpolate" not in command:
            for binding in bindings:
                if "|" not in binding:
                    raise ValueError("secret environment binding must use NAME|PATH")
                name, secret_path = binding.split("|", 1)
                if not ENV_NAME_RE.fullmatch(name) or not secret_path:
                    raise ValueError("invalid secret environment binding")
                current = environment.get(name, "")
                if current and current.strip().lower() != "secret":
                    continue
                secret = get_secret(secret_path)
                secrets.append(secret)
                environment[name] = bytes(secret).decode("utf-8")

        os.execvpe(command[0], command, environment)
    finally:
        for secret in secrets:
            wipe(secret)


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    get_parser = subparsers.add_parser("get-secret")
    get_parser.add_argument("secret_path")

    set_parser = subparsers.add_parser("set-secret")
    set_parser.add_argument("secret_path")

    check_parser = subparsers.add_parser("check-secret")
    check_parser.add_argument("operation", choices=("get", "set"))
    check_parser.add_argument("secret_path")

    run_parser = subparsers.add_parser("run-with-secrets")
    run_parser.add_argument("--secret-env", action="append", default=[])
    run_parser.add_argument("command_args", nargs=argparse.REMAINDER)

    args = parser.parse_args()
    harden_process()

    try:
        if args.command == "get-secret":
            run_get(args.secret_path)
        elif args.command == "set-secret":
            run_set(args.secret_path)
        elif args.command == "run-with-secrets":
            run_with_secrets(args.secret_env, args.command_args)
        else:
            run_check(args.secret_path, args.operation)
        return 0
    except Exception as exc:
        print(f"pm-secret.py: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

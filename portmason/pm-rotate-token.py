#!/usr/bin/env python3
"""Provider-neutral token rotation coordinator."""

from __future__ import annotations

import importlib.util
import os
import pathlib
import re
import sys
import tempfile
from types import ModuleType

NAME_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")
CODE_RE = re.compile(r"^[a-z][a-z0-9-]*$")


def load_file(path: pathlib.Path, name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load module: {path.name}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def wipe(value: bytearray) -> None:
    for index in range(len(value)):
        value[index] = 0


class SecretStore:
    def __init__(self, share: pathlib.Path, secret_module: ModuleType) -> None:
        self.share = share
        self.secret_module = secret_module
        self.paths = self._parse_paths(os.environ.get("SECRET_PATHS", ""))
        self.cache: dict[str, bytearray] = {}

    @staticmethod
    def _parse_paths(raw: str) -> dict[str, str]:
        result: dict[str, str] = {}
        for raw_line in raw.splitlines():
            line = raw_line.strip()
            if not line:
                continue
            if "|" not in line:
                raise ValueError(f"invalid SECRET_PATHS entry: {line}")
            name, path = (part.strip() for part in line.split("|", 1))
            if not NAME_RE.fullmatch(name) or not path:
                raise ValueError(f"invalid SECRET_PATHS entry: {line}")
            if name in result:
                raise ValueError(f"duplicate SECRET_PATHS key: {name}")
            result[name] = path
        return result

    def has(self, name: str) -> bool:
        return bool(os.environ.get(name, "")) or name in self.paths

    def _path(self, name: str) -> str | None:
        if not NAME_RE.fullmatch(name):
            raise ValueError(f"invalid secret variable name: {name}")
        if os.environ.get(name, ""):
            if os.environ.get("DEPLOY_ENV", "") != "dev":
                raise RuntimeError(
                    f"{name} contains direct secret material outside development"
                )
            return None
        path = self.paths.get(name)
        if not path:
            raise RuntimeError(f"{name} is empty and has no SECRET_PATHS entry")
        return path

    def get(self, name: str) -> bytearray:
        if name in self.cache:
            return bytearray(self.cache[name])
        path = self._path(name)
        if path is None:
            value = bytearray(os.environ[name].encode("utf-8"))
        else:
            value = self.secret_module.get_secret(path)
        if not value:
            raise RuntimeError(f"resolved secret is empty: {name}")
        self.cache[name] = bytearray(value)
        return bytearray(value)

    def check_settable(self, name: str) -> None:
        path = self._path(name)
        if path is not None:
            self.secret_module.provider_function(path, "set_secret")
            return
        env_file = pathlib.Path(os.environ.get("ENV_FILE", ""))
        if not env_file.is_file() or not os.access(env_file, os.W_OK):
            raise RuntimeError(f"writable ENV_FILE is required for {name}")

    def set(self, name: str, value: bytearray) -> None:
        if not value:
            raise ValueError(f"refusing to store an empty secret: {name}")
        path = self._path(name)
        if path is None:
            self._set_dotenv(name, value)
        else:
            self.secret_module.set_secret(path, value)
        old = self.cache.pop(name, None)
        if old is not None:
            wipe(old)
        self.cache[name] = bytearray(value)

    @staticmethod
    def _set_dotenv(name: str, value: bytearray) -> None:
        text = value.decode("utf-8")
        if any(char in text for char in ("\n", "\r", "'")):
            raise ValueError(f"unsupported dotenv secret value: {name}")
        env_file = pathlib.Path(os.environ["ENV_FILE"])
        lines = env_file.read_text(encoding="utf-8").splitlines(keepends=True)
        replacement = f"{name}='{text}'\n"
        output: list[str] = []
        found = False
        pattern = re.compile(rf"^(?:export\s+)?{re.escape(name)}=")
        for line in lines:
            if pattern.match(line):
                if not found:
                    output.append(replacement)
                    found = True
            else:
                output.append(line)
        if not found:
            output.append(replacement)
        descriptor, temporary = tempfile.mkstemp(
            prefix=f".{env_file.name}.rotate-", dir=env_file.parent
        )
        try:
            os.fchmod(descriptor, 0o600)
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                handle.writelines(output)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, env_file)
            os.chmod(env_file, 0o600)
            os.environ[name] = text
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)

    def close(self) -> None:
        for value in self.cache.values():
            wipe(value)
        self.cache.clear()


def provider_codes(variable: str) -> tuple[str, str]:
    domain = variable.split("_", 1)[0]
    combined = os.environ.get(f"{domain}_PROVIDER_PLATFORM_CODE", "")
    provider = os.environ.get(f"{domain}_PROVIDER_CODE", "")
    platform = os.environ.get(f"{domain}_PLATFORM_CODE", "")
    if not provider and "-" in combined:
        provider = combined.split("-", 1)[0]
    if not platform and "-" in combined:
        platform = combined.split("-", 1)[1]
    if not CODE_RE.fullmatch(provider):
        raise RuntimeError(f"invalid or missing {domain}_PROVIDER_CODE")
    if platform and not CODE_RE.fullmatch(platform):
        raise RuntimeError(f"invalid {domain}_PLATFORM_CODE")
    return provider, platform


def load_optional(path: pathlib.Path, name: str) -> ModuleType | None:
    return load_file(path, name) if path.is_file() else None


def main() -> int:
    if len(sys.argv) != 2 or not NAME_RE.fullmatch(sys.argv[1]):
        print("Usage: pm-rotate-token.py VARIABLE_NAME", file=sys.stderr)
        return 2

    variable = sys.argv[1]
    share = pathlib.Path(
        os.environ.get("PORTMASON_SHARE", pathlib.Path(__file__).resolve().parent)
    )
    secret_module = load_file(share / "pm-secret.py", "portmason_secret")
    secret_module.harden_process()
    store = SecretStore(share, secret_module)
    operation = None

    try:
        provider, platform = provider_codes(variable)
        provider_file = share / f"pm-rotate-token-{provider}.py"
        if not provider_file.is_file():
            raise RuntimeError(f"token rotation provider is unavailable: {provider}")
        provider_module = load_file(
            provider_file, f"portmason_rotate_{provider.replace('-', '_')}"
        )
        rotate = getattr(provider_module, "rotate_token", None)
        if not callable(rotate):
            raise RuntimeError(f"{provider} does not implement rotate_token")

        old_secret = store.get(variable)
        operation = rotate(variable, old_secret, store)

        previous: dict[str, bytearray] = {}
        for name in operation.updates:
            store.check_settable(name)
            previous[name] = store.get(name)

        persisted: list[str] = []
        try:
            for name, value in operation.updates.items():
                store.set(name, value)
                persisted.append(name)
        except Exception:
            operation.rollback()
            for name in reversed(persisted):
                store.set(name, previous[name])
            raise
        finally:
            for value in previous.values():
                wipe(value)


        print(
            f"Token rotation complete: variable={variable} provider={provider} "
            f"platform={platform or 'native'}",
            file=sys.stderr,
        )
        return 0
    except Exception as exc:
        print(f"pm-rotate-token.py: {exc}", file=sys.stderr)
        return 2
    finally:
        if operation is not None:
            operation.close()
        store.close()


if __name__ == "__main__":
    raise SystemExit(main())

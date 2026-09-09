"""Native PostgreSQL password rotation implementation."""

from __future__ import annotations

import os
import pathlib
import secrets
import subprocess
import time
import urllib.parse


def _text(value: bytearray) -> str:
    return bytes(value).decode("utf-8")


def _connection_url(store) -> tuple[str, str]:
    for name in ("DB_DIRECT_URL", "DB_URL"):
        if store.has(name):
            return name, _text(store.get(name))
    raise RuntimeError("DB_PASSWORD rotation requires DB_DIRECT_URL or DB_URL")


def _replace_password(url: str, old_password: str, new_password: str) -> str:
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme not in ("postgres", "postgresql"):
        raise ValueError("unsupported PostgreSQL URL")
    if parsed.username is None or parsed.password is None or parsed.hostname is None:
        raise ValueError("PostgreSQL URL must contain user, password, and host")
    if urllib.parse.unquote(parsed.password) != old_password:
        raise ValueError("database URL password does not match DB_PASSWORD")
    user = urllib.parse.quote(urllib.parse.unquote(parsed.username), safe="")
    password = urllib.parse.quote(new_password, safe="")
    host = parsed.hostname
    if ":" in host:
        host = f"[{host}]"
    if parsed.port is not None:
        host = f"{host}:{parsed.port}"
    netloc = f"{user}:{password}@{host}"
    return urllib.parse.urlunsplit(
        (parsed.scheme, netloc, parsed.path, parsed.query, parsed.fragment)
    )


def _details(url: str, expected_user: str) -> tuple[str, str, str, str]:
    parsed = urllib.parse.urlsplit(url)
    user = urllib.parse.unquote(parsed.username or "")
    password = urllib.parse.unquote(parsed.password or "")
    database = parsed.path.lstrip("/")
    if user != expected_user or not password or not parsed.hostname or not database:
        raise ValueError("database URL does not match the canonical PostgreSQL identity")
    return parsed.hostname, str(parsed.port or 5432), user, database


def _db_rt(
    host: str,
    port: str,
    user: str,
    password: bytearray,
    database: str,
    arguments: list[str],
    sql: str | None = None,
    sql_secret: bytearray | None = None,
) -> subprocess.CompletedProcess[bytes]:
    environment = os.environ.copy()
    environment.update(
        {
            "PM_DB_RT_HOST": host,
            "PM_DB_RT_PORT": port,
            "PM_DB_RT_USER": user,
            "PM_DB_RT_PASSWORD": _text(password),
            "PM_DB_RT_DATABASE": database,
        }
    )
    if sql_secret is not None:
        environment["PM_DB_SQL_SECRET"] = _text(sql_secret)

    override = os.environ.get("PM_ROTATE_TOKEN_DB_RT", "")
    if override:
        command = [override, *arguments]
    else:
        script = r'''
set -Eeuo pipefail
. "${PORTMASON_SHARE}/pm-helpers" --minimal
bridge="${PORTMASON_SHARE}/pm-db-bridge-${DB_PROVIDER_CODE}-${DB_PLATFORM_CODE}"
[[ -r "$bridge" ]] || { echo "database bridge unavailable: $bridge" >&2; exit 2; }
. "$bridge" --minimal
db_rt "$@"
'''
        command = [
            "bash", "--noprofile", "--norc", "-c", script,
            "pm-rotate-token-db-rt", *arguments,
        ]
    return subprocess.run(
        command,
        input=None if sql is None else sql.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=environment,
        check=True,
    )


class Rotation:
    def __init__(
        self,
        host: str,
        port: str,
        user: str,
        database: str,
        old_password: bytearray,
        new_password: bytearray,
        updates: dict[str, bytearray],
    ) -> None:
        self.host = host
        self.port = port
        self.user = user
        self.database = database
        self.old_password = bytearray(old_password)
        self.new_password = bytearray(new_password)
        self.updates = updates

    def _change(self, connection_password: bytearray, replacement: bytearray) -> None:
        sql = r"""
\getenv db_password PM_DB_SQL_SECRET
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'db_user', :'db_password') \gexec
"""
        _db_rt(
            self.host, self.port, self.user, connection_password, self.database,
            [f"--set=db_user={self.user}", "--file=-"], sql, replacement,
        )

    def verify(self, password: bytearray, attempts: int = 1) -> None:
        last_error: Exception | None = None
        for attempt in range(attempts):
            try:
                _db_rt(
                    self.host, self.port, self.user, password, self.database,
                    ["--quiet", "--tuples-only", "--no-align", "--command", "SELECT 1;"],
                )
                return
            except Exception as exc:
                last_error = exc
                if attempt + 1 < attempts:
                    time.sleep(2)
        raise RuntimeError(f"PostgreSQL credential verification failed: {last_error}")

    def rollback(self) -> None:
        self._change(self.new_password, self.old_password)
        self.verify(self.old_password)

    def close(self) -> None:
        for value in (self.old_password, self.new_password, *self.updates.values()):
            for index in range(len(value)):
                value[index] = 0


def rotate_token(variable: str, old_secret: bytearray, store) -> Rotation:
    if variable != "DB_PASSWORD":
        raise RuntimeError(f"PostgreSQL rotation is not implemented for {variable}")

    user = os.environ.get("DB_USER", "")
    if not user:
        raise RuntimeError("DB_USER is required")

    _, connection_url = _connection_url(store)
    old_text = _text(old_secret)
    host, port, connection_user, database = _details(connection_url, user)

    update_names = ["DB_PASSWORD"]
    for name in ("DB_URL", "DB_DIRECT_URL"):
        if store.has(name):
            update_names.append(name)
    for name in update_names:
        store.check_settable(name)

    new_password = bytearray(secrets.token_urlsafe(48).encode("ascii"))
    updates = {"DB_PASSWORD": bytearray(new_password)}
    for name in update_names[1:]:
        current_url = _text(store.get(name))
        updates[name] = bytearray(
            _replace_password(current_url, old_text, _text(new_password)).encode("utf-8")
        )

    operation = Rotation(
        host, port, connection_user, database, old_secret, new_password, updates
    )
    operation._change(operation.old_password, operation.new_password)
    operation.verify(operation.new_password)
    return operation

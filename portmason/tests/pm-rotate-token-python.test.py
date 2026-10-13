#!/usr/bin/env python3
from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest
import urllib.parse

STAGE = pathlib.Path(__file__).resolve().parents[1]
FILES = (
    "pm-rotate-token.py",
    "pm-rotate-token-postgres.py",
    "pm-secret.py",
)


class RotateTokenTest(unittest.TestCase):
    def fixture(self, fail_name: str = ""):
        temporary = tempfile.TemporaryDirectory()
        root = pathlib.Path(temporary.name)
        share = root / "share"
        values = root / "values"
        share.mkdir()
        values.mkdir()
        for name in FILES:
            shutil.copy2(STAGE / name, share / name)

        (share / "pm-secret-provider-test.py").write_text(
            """
import os
import pathlib

ROOT = pathlib.Path(os.environ["PM_TEST_VALUES"])
TRACE = pathlib.Path(os.environ["PM_TEST_TRACE"])

def get_secret(name):
    with TRACE.open("a", encoding="utf-8") as handle:
        handle.write(f"get:{name}\\n")
    return bytearray((ROOT / name).read_bytes())

def set_secret(name, value):
    with TRACE.open("a", encoding="utf-8") as handle:
        handle.write(f"set:{name}\\n")
    if os.environ.get("PM_TEST_FAIL_NAME") == name:
        raise RuntimeError(f"forced set failure: {name}")
    (ROOT / name).write_bytes(value)
""".lstrip(),
            encoding="utf-8",
        )

        db_runtime = root / "fake-db-rt"
        db_runtime.write_text(
            """#!/usr/bin/env bash
set -Eeuo pipefail
input="$(dd bs=4096 2>/dev/null || true)"
current="$(<"$PM_TEST_DB_STATE")"
[[ "$PM_DB_RT_PASSWORD" == "$current" ]] || exit 41
if [[ "$input" == *"ALTER ROLE"* ]]; then
  printf '%s' "$PM_DB_SQL_SECRET" >"$PM_TEST_DB_STATE"
  printf 'alter\\n' >>"$PM_TEST_TRACE"
elif [[ "$input" == *"pg_terminate_backend"* ]]; then
  printf 'reset\\n0\\n' | tee -a "$PM_TEST_TRACE"
else
  printf 'verify\\n1\\n' | tee -a "$PM_TEST_TRACE"
fi
""",
            encoding="utf-8",
        )
        db_runtime.chmod(0o700)

        old = "old-password"
        for name, value in {
            "DB_PASSWORD": old,
            "DB_URL": f"postgresql://app:{old}@pooler:5432/app?sslmode=require",
            "DB_DIRECT_URL": f"postgresql://app:{old}@direct:5432/app?sslmode=require",
        }.items():
            (values / name).write_text(value, encoding="utf-8")
        state = root / "db-state"
        state.write_text(old, encoding="utf-8")
        trace = root / "trace"
        trace.touch()

        env = os.environ.copy()
        env.update(
            {
                "PORTMASON_SHARE": str(share),
                "DEPLOY_ENV": "prd",
                "DB_PROVIDER_PLATFORM_CODE": "postgres-local",
                "DB_PROVIDER_CODE": "postgres",
                "DB_PLATFORM_CODE": "local",
                "DB_USER": "app",
                "DB_PASSWORD": "",
                "DB_URL": "",
                "DB_DIRECT_URL": "",
                "SECRET_PATHS": "\n".join(
                    f"{name}|test:{name}"
                    for name in ("DB_PASSWORD", "DB_URL", "DB_DIRECT_URL")
                ),
                "PM_ROTATE_TOKEN_DB_RT": str(db_runtime),
                "PM_TEST_VALUES": str(values),
                "PM_TEST_DB_STATE": str(state),
                "PM_TEST_TRACE": str(trace),
                "PM_TEST_FAIL_NAME": fail_name,
            }
        )
        return temporary, root, share, values, state, trace, env

    def test_success_changes_db_then_persists_secrets(self):
        fixture = self.fixture()
        temporary, root, share, values, state, trace, env = fixture
        self.addCleanup(temporary.cleanup)
        result = subprocess.run(
            ["python3", str(share / "pm-rotate-token.py"), "DB_PASSWORD"],
            env=env,
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        new = (values / "DB_PASSWORD").read_text(encoding="utf-8")
        self.assertNotEqual(new, "old-password")
        self.assertEqual(state.read_text(encoding="utf-8"), new)
        for name in ("DB_URL", "DB_DIRECT_URL"):
            password = urllib.parse.unquote(
                urllib.parse.urlsplit(
                    (values / name).read_text(encoding="utf-8")
                ).password
            )
            self.assertEqual(password, new)
        events = trace.read_text(encoding="utf-8").splitlines()
        self.assertLess(events.index("alter"), events.index("set:DB_PASSWORD"))
        self.assertNotIn("reset", events)

    def test_secret_failure_restores_database_and_written_secret(self):
        fixture = self.fixture("DB_URL")
        temporary, root, share, values, state, trace, env = fixture
        self.addCleanup(temporary.cleanup)
        result = subprocess.run(
            ["python3", str(share / "pm-rotate-token.py"), "DB_PASSWORD"],
            env=env,
            cwd=root,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertEqual(result.returncode, 2)
        self.assertEqual(state.read_text(encoding="utf-8"), "old-password")
        self.assertEqual(
            (values / "DB_PASSWORD").read_text(encoding="utf-8"), "old-password"
        )
        self.assertNotIn("reset", trace.read_text(encoding="utf-8").splitlines())


if __name__ == "__main__":
    unittest.main()

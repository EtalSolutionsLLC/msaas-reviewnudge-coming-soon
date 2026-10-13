#!/usr/bin/env python3
"""Portmason Secret Manager implementation for Portmason's Python secret router."""

from __future__ import annotations

import os
import subprocess
from typing import Any

DEFAULT_SOPS_FILE = os.environ.get("DEFAULT_SOPS_FILE")

def parse_reference(secret_ref: str) -> tuple[str, str]:
    if ":" in secret_ref:
        sops_file, secret_name = secret_ref.split(":", 1)
    else:
        sops_file = DEFAULT_SOPS_FILE
        secret_name = secret_ref
    if not sops_file:
        raise ValueError("Portmason secret reference requires SOPS_FILE")
    if not secret_name:
        raise ValueError("Portmason secret reference requires secret name")
    return sops_file, secret_name


def access_token(deployment_id: str) -> str:
    # NOOPd for portmason
    return ""


def api_request(
    method: str,
    url: str,
    deployment_id: str,
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    # NOOP for Portmason
    return {}

def get_secret(key: str| None = None) -> bytearray:
	"""
	Return a single secret value from a SOPS-encrypted YAML file.

	Example:
		password = get_secret("database.password")
	"""

	filename, key = parse_reference(key)
	filename = filename or DEFAULT_SOPS_FILE

	if not filename:
		raise ValueError("DEFAULT_SOPS_FILE is not defined")

	path = "".join(f'["{part}"]' for part in key.split("."))

	result = subprocess.run(
		[
			"sops",
			"--decrypt",
			"--extract",
			path,
			filename,
		],
		capture_output=True,
		text=True,
		check=True,
	)

	return bytearray(result.stdout.strip(), "utf-8")


def set_secret(key: str, value: bytearray | None = None,) -> str:
	"""
	Update a single key in a SOPS-encrypted file.

	Examples:
   		set_secret("api_key", b"abc123")
   		set_secret("secrets_filepath:api_key", b"abc123")

    	set_secret("database.password", b"secret123")
		set_secret("secrets_filepath:database.password", b"secret123")          
	"""

	filename, key = parse_reference(key)
	filename = filename or DEFAULT_SOPS_FILE

	if not filename:
		raise ValueError("DEFAULT_SOPS_FILE is not defined")

	strValue = value.decode("utf-8")

	path = "".join(f'["{part}"]' for part in key.split("."))

	subprocess.run(
		[
			"sops",
			"--set",
			f'{path} "{strValue}"',
			filename,
		],
		check=True,
	)

	return key
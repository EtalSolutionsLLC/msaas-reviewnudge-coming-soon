#!/usr/bin/env python3
"""GitHub Actions implementation for Portmason's Python secret router."""

from __future__ import annotations

import base64
import ctypes
import ctypes.util
import json
import os
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

API_BASE = os.environ.get(
    "PM_SECRET_PROVIDER_GITHUB_API_BASE",
    "https://api.github.com",
).rstrip("/")
TIMEOUT_SECONDS = int(os.environ.get("PM_SECRET_PROVIDER_TIMEOUT_SECONDS", "30"))
SEAL_BYTES = 48
PUBLIC_KEY_BYTES = 32


def repository() -> str:
    value = (
        os.environ.get("PM_GITHUB_REPOSITORY")
        or os.environ.get("GITHUB_REPOSITORY")
        or ""
    )
    if value.count("/") != 1:
        raise ValueError("PM_GITHUB_REPOSITORY must use owner/repository")
    return value


def api_token() -> str:
    value = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or ""
    if not value:
        raise ValueError("GH_TOKEN or GITHUB_TOKEN is required")
    return value


def api_request(
    method: str,
    path: str,
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    body = None
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {api_token()}",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if payload is not None:
        body = json.dumps(payload, separators=(",", ":")).encode("ascii")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        f"{API_BASE}{path}",
        data=body,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            response_body = response.read()
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"GitHub API returned HTTP {exc.code}") from exc
    if not response_body:
        return {}
    return json.loads(response_body)


def get_secret(secret_name: str) -> bytearray:
    if not secret_name.replace("_", "").isalnum():
        raise ValueError("invalid GitHub Actions secret name")
    injected = os.environ.get(secret_name)
    if not injected:
        raise RuntimeError(
            "GitHub does not expose stored secret values; "
            f"{secret_name} must be injected into this process"
        )
    return bytearray(injected.encode("utf-8"))


def sealed_box_encrypt(value: bytearray, public_key: bytes) -> str:
    if len(public_key) != PUBLIC_KEY_BYTES:
        raise RuntimeError("GitHub returned an invalid public key")
    library_name = ctypes.util.find_library("sodium")
    if not library_name:
        raise RuntimeError("libsodium is required to update GitHub secrets")
    sodium = ctypes.CDLL(library_name)
    if sodium.sodium_init() < 0:
        raise RuntimeError("libsodium initialization failed")
    sodium.crypto_box_seal.argtypes = [
        ctypes.c_void_p,
        ctypes.c_void_p,
        ctypes.c_ulonglong,
        ctypes.c_void_p,
    ]
    sodium.crypto_box_seal.restype = ctypes.c_int

    ciphertext = (ctypes.c_ubyte * (len(value) + SEAL_BYTES))()
    plaintext = (ctypes.c_ubyte * len(value)).from_buffer(value)
    key = (ctypes.c_ubyte * len(public_key)).from_buffer_copy(public_key)
    if sodium.crypto_box_seal(ciphertext, plaintext, len(value), key) != 0:
        raise RuntimeError("GitHub secret encryption failed")
    return base64.b64encode(bytes(ciphertext)).decode("ascii")


def set_secret(secret_name: str, value: bytearray) -> None:
    if not value:
        raise ValueError("refusing to store an empty secret")
    repo = repository()
    owner, name = repo.split("/", 1)
    root = (
        f"/repos/{urllib.parse.quote(owner, safe='')}/"
        f"{urllib.parse.quote(name, safe='')}/actions/secrets"
    )
    key_result = api_request("GET", f"{root}/public-key")
    key_id = str(key_result.get("key_id", ""))
    encoded_key = str(key_result.get("key", ""))
    if not key_id or not encoded_key:
        raise RuntimeError("GitHub did not return a repository public key")
    public_key = base64.b64decode(encoded_key, validate=True)
    encrypted_value = sealed_box_encrypt(value, public_key)
    api_request(
        "PUT",
        f"{root}/{urllib.parse.quote(secret_name, safe='')}",
        {"encrypted_value": encrypted_value, "key_id": key_id},
    )

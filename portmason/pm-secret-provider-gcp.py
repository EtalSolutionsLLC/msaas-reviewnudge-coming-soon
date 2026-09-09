#!/usr/bin/env python3
"""GCP Secret Manager implementation for Portmason's Python secret router."""

from __future__ import annotations

import base64
import json
import os
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

API_BASE = os.environ.get(
    "PM_SECRET_PROVIDER_GCP_API_BASE",
    "https://secretmanager.googleapis.com/v1",
).rstrip("/")
TIMEOUT_SECONDS = int(os.environ.get("PM_SECRET_PROVIDER_TIMEOUT_SECONDS", "30"))


def parse_reference(secret_ref: str) -> tuple[str, str]:
    if ":" in secret_ref:
        project_id, secret_name = secret_ref.split(":", 1)
    else:
        project_id = (
            os.environ.get("DEPLOYMENT_ID")
            or os.environ.get("GCP_PROJECT_ID")
            or os.environ.get("GOOGLE_CLOUD_PROJECT")
            or ""
        )
        secret_name = secret_ref
    if not project_id or not secret_name:
        raise ValueError("GCP secret reference requires project and secret name")
    return project_id, secret_name


def access_token(project_id: str) -> str:
    configured = os.environ.get("GOOGLE_OAUTH_ACCESS_TOKEN", "")
    if configured:
        return configured
    completed = subprocess.run(
        ["gcloud", "auth", "print-access-token", "--project", project_id],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    token = completed.stdout.strip().decode("ascii")
    if not token:
        raise RuntimeError("gcloud returned an empty access token")
    return token


def api_request(
    method: str,
    url: str,
    project_id: str,
    payload: dict[str, Any] | None = None,
) -> dict[str, Any]:
    body = None
    headers = {
        "Accept": "application/json",
        "Authorization": f"Bearer {access_token(project_id)}",
    }
    if payload is not None:
        body = json.dumps(payload, separators=(",", ":")).encode("ascii")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            response_body = response.read()
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"GCP Secret Manager API returned HTTP {exc.code}") from exc
    if not response_body:
        return {}
    return json.loads(response_body)


def get_secret(secret_ref: str) -> bytearray:
    project_id, secret_name = parse_reference(secret_ref)
    project = urllib.parse.quote(project_id, safe="")
    secret = urllib.parse.quote(secret_name, safe="")
    result = api_request(
        "GET",
        f"{API_BASE}/projects/{project}/secrets/{secret}/versions/latest:access",
        project_id,
    )
    encoded = result.get("payload", {}).get("data", "")
    if not encoded:
        raise RuntimeError("GCP Secret Manager returned an empty payload")
    return bytearray(base64.b64decode(encoded, validate=True))


def set_secret(secret_ref: str, value: bytearray) -> str:
    if not value:
        raise ValueError("refusing to store an empty secret")
    project_id, secret_name = parse_reference(secret_ref)
    project = urllib.parse.quote(project_id, safe="")
    secret = urllib.parse.quote(secret_name, safe="")
    encoded = base64.b64encode(value).decode("ascii")
    result = api_request(
        "POST",
        f"{API_BASE}/projects/{project}/secrets/{secret}:addVersion",
        project_id,
        {"payload": {"data": encoded}},
    )
    version = str(result.get("name", ""))
    if not version:
        raise RuntimeError("GCP Secret Manager did not return a version name")
    return version

#!/usr/bin/env python3
import datetime as dt
import hashlib
import json
import os
import pathlib
import random
import signal
import sys
import time
import urllib.error
import urllib.request

UTC = dt.timezone.utc
STOP = False


def log(level, message, **fields):
    record = {"level": level, "message": message, **fields}
    print(json.dumps(record, sort_keys=True, separators=(",", ":")), file=sys.stderr, flush=True)


def on_signal(_signum, _frame):
    global STOP
    STOP = True


signal.signal(signal.SIGTERM, on_signal)
signal.signal(signal.SIGINT, on_signal)


def env(name, default=""):
    return os.environ.get(name, default).strip()


def now_utc():
    return dt.datetime.now(tz=UTC)


def parse_ts(value):
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    return dt.datetime.fromisoformat(text).astimezone(UTC)


def iso(value):
    return value.astimezone(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def atomic_write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(value + "\n", encoding="utf-8")
    tmp.replace(path)


def request_json(url, method="GET", headers=None, body=None, timeout=30, retry=True):
    payload = None if body is None else json.dumps(body, separators=(",", ":")).encode()
    merged = {"Accept": "application/json", **(headers or {})}
    if payload is not None:
        merged.setdefault("Content-Type", "application/json")
    attempts = 0
    while True:
        attempts += 1
        try:
            req = urllib.request.Request(url, data=payload, headers=merged, method=method)
            with urllib.request.urlopen(req, timeout=timeout) as response:
                raw = response.read()
                return response.status, json.loads(raw or b"{}")
        except urllib.error.HTTPError as error:
            raw = error.read()
            try:
                parsed = json.loads(raw or b"{}")
            except Exception:
                parsed = {"message": raw.decode(errors="replace")[:1000]}
            if retry and error.code in {423, 429, 500, 502, 503, 504} and attempts < 8:
                delay = min(60.0, (2 ** (attempts - 1)) + random.random())
                log("warn", "transient HTTP failure", status=error.code, attempt=attempts, delay_seconds=round(delay, 2))
                time.sleep(delay)
                continue
            return error.code, parsed
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            if not retry or attempts >= 8:
                raise
            delay = min(60.0, (2 ** (attempts - 1)) + random.random())
            log("warn", "transient network failure", error=str(error), attempt=attempts, delay_seconds=round(delay, 2))
            time.sleep(delay)


def severity_text(record):
    text = str(record.get("severity_text") or "INFO").strip().upper()
    return text or "INFO"


def normalize(record, project, branch, environment):
    if not isinstance(record, dict):
        raise ValueError("log record is not an object")
    observed = str(record.get("timestamp") or "").strip()
    message = record.get("message")
    if not observed or message is None:
        raise ValueError("log record lacks timestamp or message")
    message = message if isinstance(message, str) else json.dumps(message, sort_keys=True, separators=(",", ":"))
    source_name = str(record.get("source") or "pg_endpoint")
    entity_id = str(record.get("entity_id") or "")
    service = str(record.get("service_name") or "postgres")
    attributes = record.get("attributes") if isinstance(record.get("attributes"), dict) else {}
    attributes = {
        **attributes,
        "neon_project_id": project,
        "neon_branch_id": branch,
        "neon_source": source_name,
        "neon_scope_name": str(record.get("scope_name") or ""),
    }
    identity = json.dumps({
        "provider": "neon",
        "project": project,
        "branch": branch,
        "timestamp": observed,
        "source": source_name,
        "entity_id": entity_id,
        "service": service,
        "message": message,
        "trace_id": str(record.get("trace_id") or ""),
        "span_id": str(record.get("span_id") or ""),
    }, sort_keys=True, separators=(",", ":"))
    correlation = str(attributes.get("correlation_id") or attributes.get("correlationId") or "")
    return {
        "event_id": hashlib.sha256(identity.encode()).hexdigest(),
        "observed_at": observed,
        "source": "neon",
        "provider": "neon",
        "environment": environment or "unknown",
        "service": service,
        "severity": severity_text(record),
        "severity_number": int(record.get("severity_number") or 9),
        "message": message,
        "resource_type": source_name,
        "resource_id": entity_id,
        "scope_type": "branch",
        "scope_id": branch,
        "trace_id": str(record.get("trace_id") or ""),
        "span_id": str(record.get("span_id") or ""),
        "correlation_id": correlation,
        "attributes": attributes,
    }


def post_log(url, record):
    status, response = request_json(url, method="POST", body=record, timeout=30, retry=True)
    if status < 200 or status >= 300:
        raise RuntimeError(f"observability ingestion rejected log with HTTP {status}: {response}")


def append_quarantine(path, record, error):
    path.parent.mkdir(parents=True, exist_ok=True)
    entry = {"at": iso(now_utc()), "error": str(error), "record": record}
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(entry, sort_keys=True, separators=(",", ":")) + "\n")


def query_page(api_url, api_key, body):
    return request_json(
        api_url,
        method="POST",
        headers={"Authorization": f"Bearer {api_key}"},
        body=body,
        timeout=int(env("NEON_API_MAX_TIME_SECONDS", "90")),
        retry=True,
    )


def collect_window(api_url, api_key, ingest_url, project, branch, environment, start, end, quarantine):
    cursor = ""
    delivered = 0
    quarantined = 0
    while not STOP:
        body = {
            "start_time": iso(start),
            "end_time": iso(end),
            "limit": 1000,
            "sort_order": "asc",
            "source": "pg_endpoint",
        }
        if cursor:
            body["cursor"] = cursor
        status, response = query_page(api_url, api_key, body)
        if status == 404:
            reason = str(response.get("reason") or response.get("error", {}).get("reason") or "unavailable")
            return {"available": False, "reason": reason, "delivered": delivered, "quarantined": quarantined}
        if status in {401, 403}:
            raise RuntimeError(f"Neon authentication rejected with HTTP {status}")
        if status < 200 or status >= 300:
            raise RuntimeError(f"Neon logs query failed with HTTP {status}: {response}")
        logs = response.get("logs")
        if not isinstance(logs, list):
            raise RuntimeError("Neon logs response did not contain a logs array")
        for raw in logs:
            try:
                normalized = normalize(raw, project, branch, environment)
            except Exception as error:
                append_quarantine(quarantine, raw, error)
                quarantined += 1
                continue
            post_log(ingest_url, normalized)
            delivered += 1
        truncated = bool(response.get("is_truncated"))
        cursor = str(response.get("next_cursor") or "")
        if not truncated:
            return {"available": True, "delivered": delivered, "quarantined": quarantined}
        if not cursor:
            raise RuntimeError("Neon logs response was truncated without next_cursor")
    return {"available": True, "delivered": delivered, "quarantined": quarantined}


def main():
    provider_platform = env("DB_PROVIDER_PLATFORM_CODE")
    platform = env("DB_PLATFORM_CODE") or (provider_platform.rsplit("-", 1)[-1] if "-" in provider_platform else "")
    state_dir = pathlib.Path(env("OBSERVABILITY_NEON_STATE_DIR", "/var/lib/observability-neon"))
    state_dir.mkdir(parents=True, exist_ok=True)
    health = state_dir / "health.json"
    if platform and platform != "neon":
        log("info", "Neon observability log collector idle", reason="db-platform-not-neon", platform=platform)
        while not STOP:
            atomic_write(health, json.dumps({"status": "idle", "at": iso(now_utc())}))
            time.sleep(60)
        return 0

    project = env("DB_PROJECT_ID")
    branch = env("DB_BRANCH_ID")
    api_key = env("DB_API_KEY") or env("NEON_API_KEY")
    if not project or not branch or not api_key:
        log("info", "Neon \ log collector idle", reason="credentials-or-identifiers-unresolved")
        while not STOP:
            atomic_write(health, json.dumps({"status": "idle", "at": iso(now_utc())}))
            time.sleep(60)
        return 0

    api_url = f"{env('NEON_API_BASE', 'https://console.neon.tech/api/v2')}/projects/{project}/branches/{branch}/logs/query"
    ingest_url = env("OBSERVABILITY_LOG_INGEST_URL", "http://observability-log-ingest:8080/v1/logs")
    environment = env("DEPLOY_ENV", "unknown")
    interval = max(5, int(env("OBSERVABILITY_NEON_POLL_INTERVAL_SECONDS", "15")))
    overlap = max(0, int(env("OBSERVABILITY_NEON_OVERLAP_SECONDS", "30")))
    safety_lag = max(0, int(env("OBSERVABILITY_NEON_SAFETY_LAG_SECONDS", "5")))
    initial_lookback = max(60, int(env("OBSERVABILITY_NEON_INITIAL_LOOKBACK_SECONDS", "300")))
    watermark_file = state_dir / "watermark"
    quarantine = state_dir / "quarantine.ndjson"

    log("info", "Neon observability log collector started", project=project, branch=branch)
    while not STOP:
        cycle_started = now_utc()
        end = cycle_started - dt.timedelta(seconds=safety_lag)
        try:
            if watermark_file.exists():
                watermark = parse_ts(watermark_file.read_text(encoding="utf-8").strip())
            else:
                watermark = end - dt.timedelta(seconds=initial_lookback)
            start = watermark - dt.timedelta(seconds=overlap)
            if end <= start:
                time.sleep(interval)
                continue
            result = collect_window(api_url, api_key, ingest_url, project, branch, environment, start, end, quarantine)
            if not result.get("available"):
                atomic_write(health, json.dumps({"status": "unavailable", "reason": result.get("reason"), "at": iso(now_utc())}))
                log("info", "Neon observability logs unavailable", reason=result.get("reason"))
            else:
                atomic_write(watermark_file, iso(end))
                atomic_write(health, json.dumps({"status": "ok", "at": iso(now_utc()), **result}))
                if result.get("delivered") or result.get("quarantined"):
                    log("info", "Neon observability log collection complete", **result)
        except Exception as error:
            atomic_write(health, json.dumps({"status": "error", "at": iso(now_utc()), "error": str(error)[:1000]}))
            log("error", "Neon observability log collection failed", error=str(error))
        slept = 0
        while not STOP and slept < interval:
            time.sleep(1)
            slept += 1
    log("info", "Neon observability log collector stopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

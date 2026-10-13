#!/usr/bin/env python3
import importlib.util
import pathlib
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("observability_neon_pull", ROOT / "observability/neon/pull.py")
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


class NeonPullTests(unittest.TestCase):
    def test_normalize_is_deterministic(self):
        raw = {
            "timestamp": "2026-08-21T12:34:56Z",
            "message": "database error",
            "source": "pg_endpoint",
            "entity_id": "ep-123",
            "service_name": "postgres",
            "severity_number": 17,
            "severity_text": "ERROR",
            "trace_id": "a" * 32,
            "span_id": "b" * 16,
            "attributes": {"correlation_id": "corr-1"},
        }
        first = MOD.normalize(raw, "project-1", "branch-1", "prd")
        second = MOD.normalize(raw, "project-1", "branch-1", "prd")
        self.assertEqual(first["event_id"], second["event_id"])
        self.assertEqual(first["provider"], "neon")
        self.assertEqual(first["resource_type"], "pg_endpoint")
        self.assertEqual(first["correlation_id"], "corr-1")

    def test_collect_window_pages_and_quarantines_bad_records(self):
        pages = [
            (200, {
                "logs": [
                    {"timestamp": "2026-08-21T12:00:00Z", "message": "one", "source": "pg_endpoint", "attributes": {}},
                    {"message": "missing timestamp", "attributes": {}},
                ],
                "is_truncated": True,
                "next_cursor": "next-1",
            }),
            (200, {
                "logs": [
                    {"timestamp": "2026-08-21T12:00:01Z", "message": "two", "source": "pg_endpoint", "attributes": {}},
                ],
                "is_truncated": False,
            }),
        ]
        posted = []
        requests = []

        def fake_query(_url, _key, body):
            requests.append(body.copy())
            return pages.pop(0)

        with tempfile.TemporaryDirectory() as tmp, \
             mock.patch.object(MOD, "query_page", side_effect=fake_query), \
             mock.patch.object(MOD, "post_log", side_effect=lambda _url, rec: posted.append(rec)):
            result = MOD.collect_window(
                "https://example.invalid", "secret", "http://ingest", "project", "branch", "prd",
                MOD.parse_ts("2026-08-21T11:59:00Z"), MOD.parse_ts("2026-08-21T12:01:00Z"),
                pathlib.Path(tmp) / "quarantine.ndjson",
            )
            self.assertEqual(result["delivered"], 2)
            self.assertEqual(result["quarantined"], 1)
            self.assertEqual(requests[1]["cursor"], "next-1")
            self.assertEqual(len(posted), 2)
            self.assertTrue((pathlib.Path(tmp) / "quarantine.ndjson").exists())


if __name__ == "__main__":
    unittest.main()

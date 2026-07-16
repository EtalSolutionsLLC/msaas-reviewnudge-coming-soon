# Portmason Build 093 — Compact final error summary

## Changes

- Added a run-level error registry to `pm-helpers`.
- `pm-setup` prints every collected ERROR and CRITICAL message again in a compact final summary.
- Aggregate preflight details are collected for the final summary instead of being emitted as a long stream of console ERROR lines.
- Handled preflight failures no longer generate a misleading generic `unhandled command failure` entry.
- Detailed structured diagnostics remain available in the normal log output.

## Validation

- Bash syntax checks passed for `pm-helpers`, `pm-helpers-db`, and `pm-setup`.
- `pm-error-summary-build-093.test.sh` passed.
- Existing structured text-log test passed.
- Existing Compose render diagnostics test passed.

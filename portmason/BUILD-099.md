# Build 099 — Isolate Build Identity Materialization

Build 099 removes an invalid dependency between browser Build Identity and
deployment-snapshot validation.

## Changes

- Materializes Build Identity from an isolated projection of the canonical root
  `RELEASE_VERSION`, `BUILD_NUMBER`, and `VERSION` files.
- Preserves source commit and dirty-state metadata from the real project root.
- Leaves `deploy/*` validation and repair to explicit pm-version deployment
  workflows.
- Adds a regression fixture with an intentionally incomplete `deploy/prd`.
- Makes no ReviewNudge application changes.

## Quality gate

The installer test now executes both idempotent asset installation and actual
metadata materialization while an incomplete deployment snapshot is present.

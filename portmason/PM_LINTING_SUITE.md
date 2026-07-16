# PM Linting Suite

Build 092 — 2026-07-08

PM Lint turns mechanically verifiable TGF and EPC requirements into repeatable checks.

## Policy model

- `ERROR`: known non-negotiable; blocks.
- `WARNING`: known drift; blocks under `--strict`.
- `GUIDANCE`: points to the canonical direction; does not block.
- `REVIEW`: an unclassified or intentionally new pattern; blocks under `--fail-on-review`.

CI runs with `--strict` and `--fail-on-review`.

## Commands

```bash
pm-lint
pm-lint --changed origin/main
pm-lint --all
pm-lint PATH ...
pm-lint --list-rules
pm-lint --format github|json
pm-lint --strict --fail-on-review
```

Before new implementation work:

```bash
pm-capabilities search <need>
pm-patterns search <need>
```

## Rule extension

Canonical rules live in `ops/portmason/lint/rules/`. Project rules are auto-loaded from `.pm-lint/rules/`.

ID allocation:

```text
PM000-PM899  canonical Portmason rules
PM900-PM999  project/custom rules
```

A rule needs positive and negative fixtures. Rules must remain source-safe.

## Exceptions

`.pm-lint-exceptions` uses:

```text
RULE|PATH_GLOB|OWNER|APPROVED_DATE|REVIEW_DATE|REASON
```

Unknown, broad, expired, ownerless, or non-actionable exceptions fail PM000.

## Build 092 additions

- PM023: detect project-local viewport/hash behavior that bypasses `pm-viewport-navigation.js`.
- PM024: guide public HTML copy into locale-specific content catalogs.
- PM025: require PM Configuration Manager bootstrap before Compose preflight.
- PM026: require preservation evidence for configuration migration builds.
- PM027: validate preservation manifest schema.

Run `pm-lint --list-rules` for the complete authoritative catalog.

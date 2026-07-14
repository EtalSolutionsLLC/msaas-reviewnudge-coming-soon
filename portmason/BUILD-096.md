# Build 096 — Portmason Build Identity

Supersedes the withdrawn Build 094 and Build 095 artifacts. Every archive
member now lives beneath `project/`, including `project/MANIFEST.sha256` and
the embedded `project/chg.txt` and retains the reusable, framework-free Build Identity
capability for Portmason-managed web applications.

## Included

- Canonical `pm-build-info.js` browser capability.
- Canonical `pm-build-info.css` presentation layer.
- Idempotent `pm-install-web-build-info` installer.
- `Ctrl+Shift+P` / `Command+Shift+P` command palette.
- `About this build` dialog backed by `build-info.json` and `deploy-info.json`.
- Optional `[data-pm-build-info-trigger]` visible trigger contract.
- Stable allowlist of release, build, deployment, source, artifact, and verification fields.
- Capability-catalog registration, documentation, and tests.

## Consumer contract

```bash
pm-install-web-build-info \
  --site-dir "$PROJECT_ROOT/public" \
  --entry-file "$PROJECT_ROOT/public/site.template.html"
```

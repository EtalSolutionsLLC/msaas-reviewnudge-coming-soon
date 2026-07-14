# Portmason browser utilities

Portmason browser utilities are framework-free, reusable capabilities installed from `ops/portmason/web` into Portmason-managed web applications.

## Viewport Navigation

`pm-viewport-navigation.js` is the canonical viewport-navigation contract for Portmason product and corporate sites.

It exports:

- `getViewportFrame()`
- `calculateTargetScrollTop()`
- `alignViewportTarget()`
- `navigateToHash()`
- `bindViewportNavigation()`

The contract centers a requested section within the usable viewport below the sticky header. Content taller than the usable viewport is aligned beneath the header. Reduced-motion preferences are honored.

## Build Identity

`pm-build-info.js` and `pm-build-info.css` provide the canonical Portmason Build Identity interface.

The capability:

- opens a command palette with `Ctrl+Shift+P` on Windows/Linux or `Command+Shift+P` on macOS;
- exposes the `About this build` command;
- reads only the allowlisted `build-info.json` and `deploy-info.json` fields;
- displays release, build, deployment, source, artifact, and verification identity;
- supports optional visible triggers with `data-pm-build-info-trigger`;
- contains no framework, application-account, customer-data, shell, or arbitrary-command dependency.

Install it from a project setup hook:

```bash
pm-install-web-build-info \
  --site-dir "$PROJECT_ROOT/public" \
  --entry-file "$PROJECT_ROOT/public/site.template.html"
```

The installer copies the canonical assets, idempotently injects the required stylesheet and module tags, and materializes `build-info.json` through `pm-version`. Existing official metadata for the same release and build is preserved.

The standard metadata contract is:

- `/build-info.json`
- `/deploy-info.json`
- `/artifact-manifest.json`

Applications with restrictive static-file allowlists must explicitly serve those paths.

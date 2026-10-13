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

- opens a command palette with `Ctrl+Alt+M` on Windows/Linux or `Command+Option+M` on macOS;
- exposes the `Display build info` command;
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

## Consent-gated Google Tag Manager

`base/assets/js/pm-web-analytics.js` and `base/assets/css/pm-web-analytics.css` provide Portmason's local consent interface and consent-gated GTM loader.

The capability:

- sets Google Consent Mode to denied before any Google code can load;
- loads Google Tag Manager only after analytics consent is granted;
- keeps advertising and personalization storage denied;
- provides an accessible analytics preference banner and dialog;
- remembers the visitor's choice in a necessary, first-party cookie;
- removes first-party Google Analytics cookies when analytics consent is denied;
- leaves GA4 configuration, page views, and analytics events entirely to GTM.


Include these two lines
  <!-- PM:TRACKING-CONSENT-PART1 -->
  <!-- /PM:TRACKING-CONSENT-PART1 -->
directly beneath <head>

Include these two lines
  <!-- PM:TRACKING-CONSENT-PART2 -->
  <!-- /PM:TRACKING-CONSENT-PART2 -->
directly beneath <body>

Be sure to include this global var in your .env file
GTM_CONTAINER_ID=GTM-XXXXXXX

Configure the Google tag, GA4 stream, page views, events, and route scope in
the matching GTM container. The local capability deliberately has no GA4
measurement ID and emits no analytics events.

Applications that emit a Content Security Policy must allow:

- scripts from `https://www.googletagmanager.com`;
- connections to `https://www.googletagmanager.com`, `https://*.google-analytics.com`, and `https://*.analytics.google.com`;
- images from `https://*.google-analytics.com` and `https://*.googletagmanager.com`.
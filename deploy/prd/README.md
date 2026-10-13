# ReviewNudge Coming Soon Static Site

Static GitHub Pages site under `www/`.

Local quick preview:

```bash
pm-serve-bash www/index.html
```

Container preview, rendering, configuration, and deployment preparation run through Portmason:

```bash
pm-setup
```

Runtime nginx logs are persisted to:

```text
logs/runtime/
```

Run the complete static-site test suite:

```bash
node --test tests/*.test.mjs
```

## Waitlist setup

The static page sends waitlist signups to a Google Apps Script Web App.

1. Create a Google Sheet for waitlist entries.
2. Create an Apps Script project and paste `apps-script/Code.gs`.
3. Add Script Properties:
   - `SHEET_ID`: required target Sheet ID.
   - `SHEET_NAME`: optional; defaults to `Waitlist`.
   - `AUDIT_SHEET_NAME`: optional; defaults to `WaitlistAudit`.
4. Deploy the script as a Web App.
   - Execute as: Me.
   - Who has access: Anyone.
5. Copy the Web App URL into `www/assets/waitlist-config.js`.

GitHub Pages remains static. Apps Script is the small server-side bridge that writes to Google Sheets.

## Waitlist auditing and verification

Every browser submission receives a unique `trace_id`.

The browser sends one JSONP request using `action=subscribe`. The Apps Script endpoint validates, deduplicates, writes, verifies, and returns the final result in that same response.

Before reporting success, Apps Script:

- acquires a script lock so concurrent requests cannot race each other;
- rejects an existing trace ID without creating another row;
- rejects an existing normalized email address without creating another row;
- writes the trace ID into the `Waitlist` row;
- calls `SpreadsheetApp.flush()`;
- reads the saved row back and verifies the email and trace ID;
- records request, validation, write, verification, duplicate, and exception events in `WaitlistAudit`;
- hashes the email before putting it in logs or the audit sheet.

The browser displays success only when the JSONP response contains both `ok: true` and `recorded: true`. The older POST and `action=status` interfaces remain available for compatibility and independent diagnostics, but the public page does not depend on them.

## Production workflow

The GitHub Pages workflow:

- reads the pinned commit from `.portmason-tooling-ref`;
- checks out `ops-and-sops/ops/portmason` at that exact revision;
- registers the shared Portmason directory in `PATH`;
- enters `deploy/${DEPLOY_ENV}`;
- runs `pm-setup` as the authoritative orchestration entrypoint;
- uses `pm-version` to finalize and verify the generated artifact.

The workflow must not call internal Portmason implementation utilities directly. Runtime-specific rendering and deployment behavior remain owned by `pm-setup` and its selected modules.

## Slack support boundary

The public coming-soon site must not contain a Slack webhook or a general Slack integration. Slack is reserved for authenticated ReviewNudge customers contacting the Et al Solutions support team. The customer support relay belongs in the main ReviewNudge application, where tenant identity and authorization are available.

## Build 096 QA contract alignment

Build 096 aligns the regression tests and documentation with the deployed one-request JSONP waitlist implementation. It also adds a release gate proving that GitHub Pages generation delegates to `pm-setup` rather than invoking an internal Portmason renderer directly.

## Build 097 mobile launch emphasis

Build 097 makes the launch state unmistakable in the shared content catalog and moves the early-access form above the hero copy on screens up to 640px wide. Desktop and tablet retain the existing two-column and single-column reading order. All rendering and deployment preparation continue to run through `pm-setup`.

## Build 113 international launch and language support

Build 113 replaces the expired July 15 launch messaging with a brief explanation and a clear international launch date of Monday, July 20, 2026. It also adds complete content catalogs for English, Simplified Chinese, Hindi, Spanish, Standard Arabic, French, Bengali, Brazilian Portuguese, Indonesian, and Urdu.

On first visit, the page chooses the first supported language in the browser's preference list and falls back to English. A compact globe selector beside the ReviewNudge logo lets the visitor override that choice. The override is stored for one year in the `reviewnudge_language` preference cookie. Arabic and Urdu automatically use right-to-left page direction.

## Build 114 viewport-target staging

Build 114 restores the Portmason viewport surface for explicit section navigation. Clicking a same-page link centers short section content within the usable viewport and fills the remaining space above and below inside that section, preventing neighboring sections from showing through. Tall sections remain top-aligned beneath the sticky header. Wheel, touch, keyboard, and scrollbar navigation remain native and unsnapped.

## Build 116 Netherlands-first language support

Build 116 adds a complete Dutch (`nl-NL`) content bundle for the Netherlands-first international launch. Browser language detection recognizes Dutch regional preferences such as `nl-BE`, while the existing globe selector and one-year preference cookie continue to provide an explicit override. The Coming Soon site now supports the existing top ten language set plus Dutch.

## 2026-07-16 RTL rollout gate

Standard Arabic (`ar`) and Urdu (`ur-PK`) are held from the public July 20 rollout pending native-language and RTL presentation review. Their complete catalogs remain in the repository, but they are excluded from the language selector, browser-language resolution, and preference-cookie resolution. The public rollout exposes the remaining nine locales.

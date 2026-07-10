# ReviewNudge Coming Soon Static Site

Static GitHub Pages site under `www/`.

Local quick preview:

```bash
pm-serve-bash www/index.html
```

Container preview is handled by Portmason/Compose conventions:

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

The static page posts waitlist signups to a Google Apps Script Web App.

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

The Apps Script endpoint:

- writes the trace ID into the `Waitlist` row;
- records request, validation, write, verification, duplicate, and exception events in `WaitlistAudit`;
- hashes the email before putting it in logs or the audit sheet;
- calls `SpreadsheetApp.flush()` and reads the saved row back before reporting success;
- exposes a status lookup through `doGet?action=status&traceId=...`.

Because the static page submits with `mode=no-cors`, it cannot trust the POST completion alone. It polls the status endpoint through JSONP and only displays success after the matching spreadsheet row is confirmed. Failed confirmations display the trace ID so the browser console, Apps Script execution log, `WaitlistAudit`, and `Waitlist` row can be correlated.

## Slack support boundary

The public coming-soon site must not contain a Slack webhook or a general Slack integration. Slack is reserved for authenticated ReviewNudge customers contacting the Et al Solutions support team. The customer support relay belongs in the main ReviewNudge application, where tenant identity and authorization are available.

## Build 082 viewport landing adjustment

Coming-soon section landing continues to use the centralized Portmason `pm-viewport-navigation.js` contract. This build does not add page-specific scrolling or centering logic. It reduces the existing page and hero top padding to approximately one-third of the prior values so centered targets sit higher and tall targets reveal more content.

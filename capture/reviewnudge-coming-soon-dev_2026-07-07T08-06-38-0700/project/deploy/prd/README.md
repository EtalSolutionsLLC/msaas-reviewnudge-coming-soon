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

Viewport targeting test:

```bash
node --test tests/viewport-targeting.test.mjs
```

## Waitlist setup

The static page posts waitlist signups to a Google Apps Script Web App.

1. Create a Google Sheet for waitlist entries.
2. Create an Apps Script project and paste `apps-script/Code.gs`.
3. Add Script Properties:
   - `SHEET_ID`: the target Sheet ID.
   - `SHEET_NAME`: optional, defaults to `Waitlist`.
4. Deploy the script as a Web App.
   - Execute as: Me.
   - Who has access: Anyone.
5. Copy the Web App URL into `www/assets/waitlist-config.js`.

GitHub Pages remains static. Apps Script is the small server-side bridge that writes to Google Sheets.

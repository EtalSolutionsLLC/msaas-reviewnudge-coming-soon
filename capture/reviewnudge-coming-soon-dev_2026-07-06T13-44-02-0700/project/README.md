# ReviewNudge Coming Soon

Static GitHub Pages-ready coming soon page for ReviewNudge.

## Files

- `www/index.html` — production page for GitHub Pages
- `www/assets/waitlist-config.js` — waitlist endpoint configuration
- `www/assets/waitlist.js` — browser-side form submission logic
- `docker-compose.yml` — local static preview only

## Local preview

```bash
docker compose up --build
```

Open:

```text
http://localhost:3080/
```

## Production

Publish the `www/` directory with GitHub Pages.

## Waitlist

Set `window.REVIEWNUDGE_WAITLIST_ENDPOINT` in `www/assets/waitlist-config.js` to the Google Apps Script Web App URL, or leave the placeholder until the endpoint is ready.

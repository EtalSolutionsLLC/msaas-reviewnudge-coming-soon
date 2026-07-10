# Coming Soon Content Catalog

Visitor-facing copy is stored under `www/content/en-US/`:

- `public.json` — page, navigation, hero, early-access, preview, and footer copy
- `notifications.json` — progress and success messages
- `errors.json` — validation and failure messages

`www/assets/content.js` loads the catalog and hydrates elements marked with `data-copy`. Keep stable keys when editing copy. Add new keys to JSON before referencing them in HTML or JavaScript.

# Coming Soon Content Catalog

Visitor-facing copy is stored under `www/content/en-US/`:

- `public.json` — page, navigation, hero, early-access, preview, and footer copy
- `notifications.json` — progress and success messages
- `errors.json` — validation and failure messages

`www/assets/content.js` loads the catalog and hydrates elements marked with `data-copy`. Keep stable keys when editing copy. Add new keys to JSON before referencing them in HTML or JavaScript.

Build 113 includes matching catalogs for these locales:

- `en-US` — English
- `zh-CN` — Simplified Chinese
- `hi-IN` — Hindi
- `es-ES` — Spanish
- `ar` — Standard Arabic
- `fr-FR` — French
- `bn-BD` — Bengali
- `pt-BR` — Brazilian Portuguese
- `id-ID` — Indonesian
- `ur-PK` — Urdu

`www/assets/language.js` resolves the first supported browser language unless a valid `reviewnudge_language` preference cookie exists. The globe selector in the shared header writes that cookie for one year. Every locale must provide the same keys as `en-US`; Arabic and Urdu use right-to-left document direction.

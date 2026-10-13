# Coming Soon Content Catalog

Visitor-facing copy is stored under `www/content/en-US/`:

- `public.json` — page, navigation, hero, early-access, preview, and footer copy
- `notifications.json` — progress and success messages
- `errors.json` — validation and failure messages

`www/assets/content.js` loads the catalog and hydrates elements marked with `data-copy`. Keep stable keys when editing copy. Add new keys to JSON before referencing them in HTML or JavaScript.

The Coming Soon rollout publicly supports these locales:

- `en-US` — English
- `nl-NL` — Dutch
- `zh-CN` — Simplified Chinese
- `hi-IN` — Hindi
- `es-ES` — Spanish
- `fr-FR` — French
- `bn-BD` — Bengali
- `pt-BR` — Brazilian Portuguese
- `id-ID` — Indonesian

Complete Standard Arabic (`ar`) and Urdu (`ur-PK`) catalogs remain in the repository but are held from this rollout pending native-language and RTL presentation review. They are not exposed in the selector, browser-language resolution, or preference-cookie resolution.

`www/assets/language.js` resolves the first publicly supported browser language unless a valid `reviewnudge_language` preference cookie exists. The globe selector in the shared header writes that cookie for one year. Every active or held locale must provide the same keys as `en-US`.

export const DEFAULT_LOCALE = 'en-US';
export const LANGUAGE_COOKIE = 'reviewnudge_language';

export const SUPPORTED_LOCALES = Object.freeze([
  Object.freeze({ locale: 'en-US', language: 'en', direction: 'ltr' }),
  Object.freeze({ locale: 'zh-CN', language: 'zh', direction: 'ltr' }),
  Object.freeze({ locale: 'hi-IN', language: 'hi', direction: 'ltr' }),
  Object.freeze({ locale: 'es-ES', language: 'es', direction: 'ltr' }),
  Object.freeze({ locale: 'ar', language: 'ar', direction: 'rtl' }),
  Object.freeze({ locale: 'fr-FR', language: 'fr', direction: 'ltr' }),
  Object.freeze({ locale: 'bn-BD', language: 'bn', direction: 'ltr' }),
  Object.freeze({ locale: 'pt-BR', language: 'pt', direction: 'ltr' }),
  Object.freeze({ locale: 'id-ID', language: 'id', direction: 'ltr' }),
  Object.freeze({ locale: 'ur-PK', language: 'ur', direction: 'rtl' })
]);

function matchLocale(candidate) {
  const normalized = String(candidate || '').trim().replace(/_/g, '-').toLowerCase();
  if (!normalized) return null;

  return SUPPORTED_LOCALES.find(item => item.locale.toLowerCase() === normalized)
    || SUPPORTED_LOCALES.find(item => item.language === normalized.split('-')[0])
    || null;
}

export function localeDefinition(locale) {
  return matchLocale(locale) || SUPPORTED_LOCALES[0];
}

export function resolveLocale(options = {}) {
  const cookieMatch = matchLocale(options.cookieLocale);
  if (cookieMatch) return cookieMatch.locale;

  const preferred = Array.isArray(options.navigatorLanguages)
    ? options.navigatorLanguages
    : [options.navigatorLanguages];

  for (const candidate of preferred) {
    const match = matchLocale(candidate);
    if (match) return match.locale;
  }

  return DEFAULT_LOCALE;
}

export function readLocaleCookie(cookieString = '') {
  const prefix = `${LANGUAGE_COOKIE}=`;
  const entry = String(cookieString || '')
    .split(';')
    .map(value => value.trim())
    .find(value => value.startsWith(prefix));

  if (!entry) return '';

  try {
    return matchLocale(decodeURIComponent(entry.slice(prefix.length)))?.locale || '';
  } catch {
    return '';
  }
}

export function createLocaleCookie(locale, options = {}) {
  const match = matchLocale(locale);
  if (!match) return '';

  const secure = options.secure === true ? '; Secure' : '';
  return `${LANGUAGE_COOKIE}=${encodeURIComponent(match.locale)}; Max-Age=31536000; Path=/; SameSite=Lax${secure}`;
}

export function setLocaleCookie(locale, documentRef = globalThis.document, locationRef = globalThis.location) {
  if (!documentRef) return '';
  const cookie = createLocaleCookie(locale, { secure: locationRef?.protocol === 'https:' });
  if (cookie) documentRef.cookie = cookie;
  return cookie;
}

export function applyLocaleMetadata(locale, documentRef = globalThis.document) {
  const definition = localeDefinition(locale);
  const root = documentRef?.documentElement;
  if (!root) return definition.locale;

  root.lang = definition.locale;
  root.dir = definition.direction;
  root.dataset.locale = definition.locale;
  return definition.locale;
}

import { applyContent, loadContentCatalog } from './content.js';
import {
  applyLocaleMetadata,
  readLocaleCookie,
  resolveLocale,
  setLocaleCookie
} from './language.js';
import { bindWaitlist } from './waitlist.js';
import { bindViewportNavigation, navigateToHash } from './pm-viewport-navigation.js';

async function activateLocale(locale, languageSelect) {
  await loadContentCatalog({ locale });
  applyLocaleMetadata(locale, document);
  applyContent(document);
  if (languageSelect) languageSelect.value = locale;
  return locale;
}

async function start() {
  const languageSelect = document.querySelector('[data-language-select]');
  const navigatorLanguages = Array.isArray(window.navigator.languages) && window.navigator.languages.length
    ? window.navigator.languages
    : [window.navigator.language];
  let activeLocale = resolveLocale({
    cookieLocale: readLocaleCookie(document.cookie),
    navigatorLanguages
  });

  await activateLocale(activeLocale, languageSelect);
  document.documentElement.setAttribute('data-content-ready', 'true');
  document.body.removeAttribute('aria-busy');

  languageSelect?.addEventListener('change', async event => {
    const requestedLocale = event.currentTarget.value;
    languageSelect.disabled = true;
    document.body.setAttribute('aria-busy', 'true');

    try {
      activeLocale = await activateLocale(requestedLocale, languageSelect);
      setLocaleCookie(activeLocale, document, window.location);
    } catch (error) {
      languageSelect.value = activeLocale;
      window.console.error('[ReviewNudge language]', error);
    } finally {
      languageSelect.disabled = false;
      document.body.removeAttribute('aria-busy');
    }
  });

  bindWaitlist(document, window);
  bindViewportNavigation(document, {
    headerSelector: '[data-pm-sticky-header]'
  });

  if (!window.location.hash) {
    navigateToHash('#top', {
      documentRef: document,
      windowRef: window,
      headerSelector: '[data-pm-sticky-header]',
      behavior: 'auto',
      updateHistory: false
    });
  }
}

start().catch(error => {
  document.documentElement.setAttribute('data-content-ready', 'error');
  document.body.removeAttribute('aria-busy');
  window.console.error('[ReviewNudge content]', error);
});

import { applyContent, loadContentCatalog } from './content.js';
import { bindWaitlist } from './waitlist.js';
import { bindViewportNavigation, navigateToHash } from './pm-viewport-navigation.js';

async function start() {
  await loadContentCatalog();
  applyContent(document);
  document.documentElement.setAttribute('data-content-ready', 'true');
  document.body.removeAttribute('aria-busy');

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

(() => {
'use strict';

const CONSENT_COOKIE_NAME = 'pm_cookie_consent';
const CONSENT_COOKIE_MAX_AGE = 60 * 60 * 24 * 180;
const ANALYTICS_GRANTED = 'granted';
const ANALYTICS_DENIED = 'denied';
const DEFAULT_PREFERENCES_ICON = '/assets/icons/cookie-preferences.png';

const DEFAULT_COPY = Object.freeze({
  title: 'Cookie preferences',
  description: 'Essential cookies keep this site working. Optional analytics help improve it and stay off unless you allow them.',
  accept: 'Allow analytics',
  reject: 'Reject optional',
  manage: 'Manage preferences',
  preferencesTitle: 'Manage cookie preferences',
  essentialTitle: 'Essential cookies',
  essentialDescription: 'Required for security, navigation, and the features you choose to use.',
  analyticsTitle: 'Analytics cookies',
  analyticsDescription: 'Allow Google Analytics to measure visits and page use.',
  save: 'Save preferences',
  cancel: 'Cancel',
  close: 'Close cookie preferences'
});

function normalizeGtmContainerId(value) {
  const normalized = String(value || '').trim().toUpperCase();
  return /^GTM-[A-Z0-9]+$/.test(normalized) ? normalized : '';
}

function parseAnalyticsConsent(value) {
  const normalized = String(value || '').trim().toLowerCase();
  if (normalized === `v1:${ANALYTICS_GRANTED}`) return ANALYTICS_GRANTED;
  if (normalized === `v1:${ANALYTICS_DENIED}`) return ANALYTICS_DENIED;
  return '';
}

function serializeAnalyticsConsent(value) {
  return `v1:${value === ANALYTICS_GRANTED ? ANALYTICS_GRANTED : ANALYTICS_DENIED}`;
}

function ensureGoogleConsentApi() {
  window.dataLayer = window.dataLayer || [];
  window.gtag = window.gtag || function gtag() {
    window.dataLayer.push(arguments);
  };
}

function googleConsentState(analyticsStorage) {
  return {
    ad_storage: ANALYTICS_DENIED,
    ad_user_data: ANALYTICS_DENIED,
    ad_personalization: ANALYTICS_DENIED,
    analytics_storage: analyticsStorage,
    functionality_storage: ANALYTICS_GRANTED,
    personalization_storage: ANALYTICS_DENIED,
    security_storage: ANALYTICS_GRANTED
  };
}

function setDefaultGoogleConsent() {
  ensureGoogleConsentApi();
  window.gtag('consent', 'default', {
    ...googleConsentState(ANALYTICS_DENIED),
    wait_for_update: 500
  });
}

function readConsentCookie() {
  const prefix = `${CONSENT_COOKIE_NAME}=`;
  const item = String(document.cookie || '')
    .split(';')
    .map(part => part.trim())
    .find(part => part.startsWith(prefix));
  if (!item) return '';

  try {
    return parseAnalyticsConsent(decodeURIComponent(item.slice(prefix.length)));
  } catch {
    return '';
  }
}

function writeConsentCookie(value) {
  const secure = window.location.protocol === 'https:' ? '; Secure' : '';
  document.cookie = `${CONSENT_COOKIE_NAME}=${encodeURIComponent(serializeAnalyticsConsent(value))}; Path=/; Max-Age=${CONSENT_COOKIE_MAX_AGE}; SameSite=Lax${secure}`;
}

function clearAnalyticsCookies() {
  const names = String(document.cookie || '')
    .split(';')
    .map(part => part.trim().split('=')[0])
    .filter(name => /^(_ga($|_)|_gid$|_gat($|_)|_gac_)/.test(name));
  if (!names.length) return;

  const hostname = String(window.location.hostname || '').replace(/^\./, '');
  const labels = hostname.split('.').filter(Boolean);
  const domains = [''];
  for (let index = 0; index < labels.length - 1; index += 1) {
    domains.push(`; Domain=.${labels.slice(index).join('.')}`);
  }

  const secure = window.location.protocol === 'https:' ? '; Secure' : '';
  for (const name of new Set(names)) {
    for (const domain of domains) {
      document.cookie = `${name}=; Path=/; Max-Age=0; SameSite=Lax${secure}${domain}`;
    }
  }
}

function updateGoogleConsent(value, persist = true) {
  const analyticsStorage = value === ANALYTICS_GRANTED ? ANALYTICS_GRANTED : ANALYTICS_DENIED;
  ensureGoogleConsentApi();
  window.gtag('consent', 'update', googleConsentState(analyticsStorage));
  window.dataLayer.push({
    event: 'cookie_consent_update',
    analytics_storage: analyticsStorage
  });
  if (persist) writeConsentCookie(analyticsStorage);
  if (analyticsStorage === ANALYTICS_DENIED) clearAnalyticsCookies();
  window.dispatchEvent(new CustomEvent('pm:analytics-consent', {
    detail: { analyticsStorage }
  }));
  return analyticsStorage;
}

function loadGoogleTagManager(containerId) {
  if (document.querySelector('script[data-pm-gtm-loader]')) return;

  const loader = document.createElement('script');
  loader.async = true;
  loader.dataset.pmGtmLoader = '';
  loader.src = `https://www.googletagmanager.com/gtm.js?id=${encodeURIComponent(containerId)}`;
  window.dataLayer.push({
    'gtm.start': Date.now(),
    event: 'gtm.js'
  });

  const firstScript = document.getElementsByTagName('script')[0];
  if (firstScript?.parentNode) firstScript.parentNode.insertBefore(loader, firstScript.nextSibling);
  else document.head.append(loader);
}

function copyFromScript(script) {
  return {
    title: script.dataset.consentTitle || DEFAULT_COPY.title,
    description: script.dataset.consentDescription || DEFAULT_COPY.description,
    accept: script.dataset.consentAccept || DEFAULT_COPY.accept,
    reject: script.dataset.consentReject || DEFAULT_COPY.reject,
    manage: script.dataset.consentManage || DEFAULT_COPY.manage,
    preferencesTitle: script.dataset.preferencesTitle || DEFAULT_COPY.preferencesTitle,
    essentialTitle: script.dataset.essentialTitle || DEFAULT_COPY.essentialTitle,
    essentialDescription: script.dataset.essentialDescription || DEFAULT_COPY.essentialDescription,
    analyticsTitle: script.dataset.analyticsTitle || DEFAULT_COPY.analyticsTitle,
    analyticsDescription: script.dataset.analyticsDescription || DEFAULT_COPY.analyticsDescription,
    save: script.dataset.preferencesSave || DEFAULT_COPY.save,
    cancel: script.dataset.preferencesCancel || DEFAULT_COPY.cancel,
    close: script.dataset.preferencesClose || DEFAULT_COPY.close
  };
}

function appendTextElement(parent, tagName, className, text) {
  const element = document.createElement(tagName);
  if (className) element.className = className;
  element.textContent = text;
  parent.append(element);
  return element;
}

function createButton(label, action, className = '') {
  const button = document.createElement('button');
  button.type = 'button';
  button.dataset.pmConsentAction = action;
  button.className = className;
  button.textContent = label;
  return button;
}

function createPersistentPreferencesTrigger(label, iconSource) {
  const button = createButton(label, 'manage', 'pm-analytics-preferences-trigger');
  if (!iconSource) return button;

  button.classList.add('pm-analytics-preferences-trigger--icon');
  button.textContent = '';
  button.setAttribute('aria-label', label);
  button.title = label;

  const icon = document.createElement('img');
  icon.src = iconSource;
  icon.alt = '';
  icon.setAttribute('aria-hidden', 'true');
  button.append(icon);
  return button;
}

function createConsentInterface(script, initialConsent, onConsent) {
  const copy = copyFromScript(script);

  const banner = document.createElement('section');
  banner.className = 'pm-analytics-consent';
  banner.dataset.pmAnalyticsConsent = '';
  banner.setAttribute('aria-labelledby', 'pmAnalyticsConsentTitle');
  banner.setAttribute('role', 'dialog');
  banner.hidden = Boolean(initialConsent);

  const bannerCopy = document.createElement('div');
  bannerCopy.className = 'pm-analytics-consent__copy';
  const bannerTitle = appendTextElement(bannerCopy, 'h2', '', copy.title);
  bannerTitle.id = 'pmAnalyticsConsentTitle';
  appendTextElement(bannerCopy, 'p', '', copy.description);
  banner.append(bannerCopy);

  const bannerActions = document.createElement('div');
  bannerActions.className = 'pm-analytics-consent__actions';
  bannerActions.append(
    createButton(copy.accept, 'accept', 'pm-analytics-consent__primary'),
    createButton(copy.reject, 'reject'),
    createButton(copy.manage, 'manage')
  );
  banner.append(bannerActions);

  const preferencesIcon = String(script.dataset.consentPreferencesIcon || DEFAULT_PREFERENCES_ICON).trim();

  const persistentTrigger = createPersistentPreferencesTrigger(copy.manage, preferencesIcon);
  persistentTrigger.hidden = !initialConsent || Boolean(document.querySelector('[data-cookie-preferences]'));

  const dialog = document.createElement('dialog');
  dialog.className = 'pm-analytics-preferences';
  dialog.dataset.pmAnalyticsPreferences = '';
  dialog.setAttribute('aria-labelledby', 'pmAnalyticsPreferencesTitle');

  const form = document.createElement('form');
  form.method = 'dialog';
  form.className = 'pm-analytics-preferences__panel';
  const header = document.createElement('header');
  const preferencesTitle = appendTextElement(header, 'h2', '', copy.preferencesTitle);
  preferencesTitle.id = 'pmAnalyticsPreferencesTitle';
  const closeButton = createButton('×', 'close', 'pm-analytics-preferences__close');
  closeButton.setAttribute('aria-label', copy.close);
  header.append(closeButton);
  form.append(header);

  const essential = document.createElement('section');
  essential.className = 'pm-analytics-preferences__category';
  appendTextElement(essential, 'h3', '', copy.essentialTitle);
  appendTextElement(essential, 'p', '', copy.essentialDescription);
  appendTextElement(essential, 'strong', '', 'Always on');
  form.append(essential);

  const analytics = document.createElement('label');
  analytics.className = 'pm-analytics-preferences__category pm-analytics-preferences__choice';
  const analyticsCheckbox = document.createElement('input');
  analyticsCheckbox.type = 'checkbox';
  analyticsCheckbox.name = 'analytics';
  analyticsCheckbox.checked = initialConsent === ANALYTICS_GRANTED;
  const analyticsText = document.createElement('span');
  appendTextElement(analyticsText, 'strong', '', copy.analyticsTitle);
  appendTextElement(analyticsText, 'small', '', copy.analyticsDescription);
  analytics.append(analyticsCheckbox, analyticsText);
  form.append(analytics);

  const dialogActions = document.createElement('div');
  dialogActions.className = 'pm-analytics-preferences__actions';
  dialogActions.append(
    createButton(copy.cancel, 'close'),
    createButton(copy.save, 'save', 'pm-analytics-consent__primary')
  );
  form.append(dialogActions);
  dialog.append(form);

  document.body.append(banner, persistentTrigger, dialog);

  const closePreferences = () => {
    if (typeof dialog.close === 'function' && dialog.open) dialog.close();
    else dialog.removeAttribute('open');
  };

  const openPreferences = () => {
    analyticsCheckbox.checked = readConsentCookie() === ANALYTICS_GRANTED;
    if (typeof dialog.showModal === 'function' && !dialog.open) dialog.showModal();
    else dialog.setAttribute('open', '');
  };

  const saveConsent = value => {
    onConsent(value);
    banner.hidden = true;
    persistentTrigger.hidden = Boolean(document.querySelector('[data-cookie-preferences]'));
    closePreferences();
  };

  document.addEventListener('click', event => {
    const preferenceTrigger = event.target.closest?.('[data-cookie-preferences]');
    if (preferenceTrigger) {
      event.preventDefault();
      openPreferences();
      return;
    }

    const action = event.target.closest?.('[data-pm-consent-action]')?.dataset.pmConsentAction;
    if (action === 'accept') saveConsent(ANALYTICS_GRANTED);
    if (action === 'reject') saveConsent(ANALYTICS_DENIED);
    if (action === 'manage') openPreferences();
    if (action === 'save') saveConsent(analyticsCheckbox.checked ? ANALYTICS_GRANTED : ANALYTICS_DENIED);
    if (action === 'close') closePreferences();
  });

  return { openPreferences };
}

function initializePortmasonConsent() {
  const script = document.currentScript || document.querySelector('script[data-pm-web-consent]');
  if (!script || script.dataset.pmWebConsentInitialized === 'true') return null;

  const containerId = normalizeGtmContainerId(script.dataset.gtmContainerId);
  if (!containerId) {
    console.warn('Portmason Consent requires a valid GTM_CONTAINER_ID value.');
    return null;
  }

  script.dataset.pmWebConsentInitialized = 'true';
  setDefaultGoogleConsent();

  const initialConsent = readConsentCookie();
  if (initialConsent) updateGoogleConsent(initialConsent, false);
  if (initialConsent === ANALYTICS_GRANTED) loadGoogleTagManager(containerId);
  else clearAnalyticsCookies();

  let consentInterface = null;
  const applyConsent = value => {
    const analyticsStorage = updateGoogleConsent(value);
    if (analyticsStorage === ANALYTICS_GRANTED) loadGoogleTagManager(containerId);
    return analyticsStorage;
  };
  const mountConsentInterface = () => {
    if (consentInterface || !document.body) return;
    consentInterface = createConsentInterface(script, initialConsent, applyConsent);
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', mountConsentInterface, { once: true });
  } else {
    mountConsentInterface();
  }

  const api = Object.freeze({
    containerId,
    consent: () => readConsentCookie(),
    setConsent: applyConsent,
    openPreferences: () => {
      mountConsentInterface();
      consentInterface?.openPreferences();
    }
  });
  window.PortmasonConsent = api;
  window.dataLayer.push({
    event: 'pm_consent_ready',
    analytics_storage: initialConsent || ANALYTICS_DENIED
  });
  return api;
}

if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  initializePortmasonConsent();
}
})();

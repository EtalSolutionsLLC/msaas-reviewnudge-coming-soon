import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../web/base/assets/js/pm-web-analytics.js', import.meta.url), 'utf8');

function runConsent(cookie = '') {
  const cookies = new Map();
  for (const item of cookie.split(';')) {
    const [name, value = ''] = item.trim().split('=');
    if (name) cookies.set(name, value);
  }

  const insertedScripts = [];
  const bootstrapScript = {
    dataset: {
      pmWebConsent: '',
      gtmContainerId: 'GTM-TEST123',
      siteName: 'Test Site'
    },
    parentNode: {
      insertBefore(node) {
        insertedScripts.push(node);
      }
    }
  };
  const document = {
    currentScript: bootstrapScript,
    readyState: 'loading',
    body: null,
    head: {
      append(node) {
        insertedScripts.push(node);
      }
    },
    querySelector(selector) {
      if (selector === 'script[data-pm-gtm-loader]') {
        return insertedScripts.find(script => script.dataset?.pmGtmLoader === '') || null;
      }
      return null;
    },
    getElementsByTagName(name) {
      return name === 'script' ? [bootstrapScript] : [];
    },
    createElement(name) {
      return { nodeName: name.toUpperCase(), dataset: {} };
    },
    addEventListener() {}
  };
  Object.defineProperty(document, 'cookie', {
    get() {
      return [...cookies].map(([name, value]) => `${name}=${value}`).join('; ');
    },
    set(value) {
      const [pair, ...attributes] = value.split(';').map(part => part.trim());
      const [name, cookieValue = ''] = pair.split('=');
      if (attributes.some(attribute => /^Max-Age=0$/i.test(attribute))) cookies.delete(name);
      else cookies.set(name, cookieValue);
    }
  });

  const window = {
    document,
    location: {
      protocol: 'https:',
      hostname: 'www.example.com'
    },
    dispatchEvent() {}
  };
  vm.runInNewContext(source, {
    window,
    document,
    CustomEvent: class CustomEvent {
      constructor(type, init) {
        this.type = type;
        this.detail = init?.detail;
      }
    },
    Date,
    URL,
    console,
    encodeURIComponent,
    setTimeout,
    clearTimeout
  });

  return { cookies, insertedScripts, window };
}

const fresh = runConsent();
assert.equal(fresh.insertedScripts.length, 0, 'fresh visitors must not load GTM');
assert.equal(fresh.window.PortmasonConsent.consent(), '');
assert.equal(fresh.window.dataLayer[0][0], 'consent');
assert.equal(fresh.window.dataLayer[0][1], 'default');
assert.equal(fresh.window.dataLayer[0][2].analytics_storage, 'denied');

fresh.window.PortmasonConsent.setConsent('granted');
assert.equal(fresh.insertedScripts.length, 1, 'accepting analytics must load GTM');
assert.equal(
  fresh.insertedScripts[0].src,
  'https://www.googletagmanager.com/gtm.js?id=GTM-TEST123'
);
assert.equal(fresh.cookies.get('pm_cookie_consent'), 'v1%3Agranted');

const denied = runConsent('pm_cookie_consent=v1%3Adenied; _ga=old; _ga_TEST=old');
assert.equal(denied.insertedScripts.length, 0, 'denied visitors must not load GTM');
assert.equal(denied.cookies.has('_ga'), false);
assert.equal(denied.cookies.has('_ga_TEST'), false);

const malformed = runConsent('pm_cookie_consent=not-valid; _ga=old');
assert.equal(malformed.insertedScripts.length, 0, 'malformed consent must fail closed');
assert.equal(malformed.cookies.has('_ga'), false);

const granted = runConsent('pm_cookie_consent=v1%3Agranted');
assert.equal(granted.insertedScripts.length, 1, 'returning opted-in visitors must load GTM');
granted.cookies.set('_ga', 'new');
granted.window.PortmasonConsent.setConsent('denied');
assert.equal(granted.cookies.has('_ga'), false, 'revoking consent must clear GA cookies');

const nextPage = runConsent(`pm_cookie_consent=${granted.cookies.get('pm_cookie_consent')}`);
assert.equal(nextPage.insertedScripts.length, 0, 'GTM must stay off after revocation on the next page');

console.log('PASS: consent decisions gate GTM and denial clears GA cookies');

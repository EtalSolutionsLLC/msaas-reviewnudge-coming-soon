import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const moduleSource = await readFile(new URL('../www/assets/pm-viewport-navigation.js', import.meta.url), 'utf8');
const navigationModule = await import(`data:text/javascript;base64,${Buffer.from(moduleSource).toString('base64')}`);
const {
  bindViewportNavigation,
  navigateToHash,
  calculateTargetScrollTop,
  getViewportFrame
} = navigationModule;

function createFakePage({ targetHeight = 360, targetTop = 900, headerHeight = 64, viewportHeight = 800 } = {}) {
  const styleValues = new Map();
  const scrollCalls = [];
  const listeners = new Map();
  const targets = new Map();

  const header = {
    hidden: false,
    getBoundingClientRect: () => ({ height: headerHeight })
  };

  const updates = {
    id: 'updates',
    hidden: false,
    getBoundingClientRect: () => ({ top: targetTop, height: targetHeight })
  };

  targets.set('updates', updates);

  const windowRef = {
    innerHeight: viewportHeight,
    scrollY: 0,
    pageYOffset: 0,
    location: {
      href: 'http://localhost:8000/',
      origin: 'http://localhost:8000',
      pathname: '/',
      search: '',
      hash: ''
    },
    history: {
      pushed: [],
      pushState(_state, _title, url) {
        this.pushed.push(url);
        windowRef.location.hash = url.includes('#') ? url.slice(url.indexOf('#')) : '';
      },
      replaceState(_state, _title, url) {
        this.pushed.push(url);
        windowRef.location.hash = url.includes('#') ? url.slice(url.indexOf('#')) : '';
      }
    },
    getComputedStyle(element) {
      return { position: element === header ? 'sticky' : 'static' };
    },
    matchMedia() {
      return { matches: true };
    },
    requestAnimationFrame(callback) {
      callback();
      return 1;
    },
    addEventListener(type, handler) {
      listeners.set(type, handler);
    },
    removeEventListener(type) {
      listeners.delete(type);
    },
    scrollTo(call) {
      scrollCalls.push(call);
    }
  };

  const documentRef = {
    defaultView: windowRef,
    documentElement: {
      style: {
        setProperty(name, value) {
          styleValues.set(name, value);
        }
      }
    },
    querySelector(selector) {
      return selector === '[data-pm-sticky-header]' ? header : null;
    },
    getElementById(id) {
      return targets.get(id) || null;
    },
    addEventListener(type, handler) {
      listeners.set(type, handler);
    },
    removeEventListener(type) {
      listeners.delete(type);
    },
    contains() {
      return true;
    }
  };

  return { documentRef, windowRef, listeners, scrollCalls, styleValues, updates };
}

test('coming soon page includes the shared Portmason viewport navigation module', async () => {
  const html = await readFile(new URL('../www/index.html', import.meta.url), 'utf8');
  assert.match(html, /\.\/assets\/pm-viewport-navigation\.js/);
  assert.match(html, /bindViewportNavigation\(document/);
  assert.match(html, /id="updates"[^>]*data-pm-viewport-target/);
});

test('centers the short updates section inside the usable viewport below the sticky header', () => {
  const page = createFakePage({ targetTop: 900, targetHeight: 360, headerHeight: 64, viewportHeight: 800 });
  const result = navigateToHash('#updates', {
    documentRef: page.documentRef,
    windowRef: page.windowRef,
    headerSelector: '[data-pm-sticky-header]',
    behavior: 'auto'
  });

  assert.equal(result, true);
  assert.deepEqual(page.windowRef.history.pushed, ['/#updates']);
  assert.equal(page.scrollCalls.length, 1);
  assert.equal(page.scrollCalls[0].top, 648);
  assert.equal(page.scrollCalls[0].behavior, 'auto');
  assert.equal(page.styleValues.get('--pm-header-h'), '64px');
  assert.equal(page.styleValues.get('--pm-usable-vh'), '736px');
});

test('top-aligns a target that is taller than the usable viewport', () => {
  const frame = getViewportFrame({ viewportHeight: 800, headerHeight: 64 });
  const top = calculateTargetScrollTop({
    targetTop: 900,
    targetHeight: 900,
    currentScrollY: 0,
    frame
  });

  assert.equal(top, 836);
});

test('clicking an in-page anchor prevents default navigation and uses viewport targeting', () => {
  const page = createFakePage({ targetTop: 900, targetHeight: 360, headerHeight: 64, viewportHeight: 800 });
  const unbind = bindViewportNavigation(page.documentRef, {
    documentRef: page.documentRef,
    windowRef: page.windowRef,
    headerSelector: '[data-pm-sticky-header]',
    behavior: 'auto'
  });

  let prevented = false;
  const link = { href: 'http://localhost:8000/#updates' };
  const event = {
    target: { closest: () => link },
    preventDefault() { prevented = true; }
  };

  page.listeners.get('click')(event);

  assert.equal(prevented, true);
  assert.equal(page.scrollCalls.length, 1);
  assert.equal(page.scrollCalls[0].top, 648);

  unbind();
});

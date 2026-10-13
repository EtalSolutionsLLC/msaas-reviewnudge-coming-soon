import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const runtime = require('../web/pm-collections.js');

const manifest = {
  mode: 'publication',
  selection: {
    strategy: 'weekday-week-of-month',
    timezone: 'America/Los_Angeles',
    visibleItems: 1
  }
};

test('browser runtime derives the weekday slot in the collection timezone', () => {
  assert.equal(runtime.currentSlot(manifest, new Date('2026-08-15T06:59:59Z')), 5);
  assert.equal(runtime.currentSlot(manifest, new Date('2026-08-15T07:00:00Z')), 6);
});

test('browser runtime rotates filesystem items by slot and week sequence', () => {
  const items = [
    { id: 1, slot: 6, status: 'Published', dateFirstDisplayed: '2026-08-01', displayAfter: [] },
    { id: 2, slot: 6, status: 'Published', dateFirstDisplayed: '2026-08-08', displayAfter: [] },
    { id: 3, slot: 6, status: 'Published', dateFirstDisplayed: '2026-08-15', displayAfter: [] },
    { id: 4, slot: 6, status: 'Published', dateFirstDisplayed: '2026-08-22', displayAfter: [] }
  ];
  assert.equal(runtime.weekOfMonth(manifest, new Date('2026-08-15T19:00:00Z')), 3);
  assert.equal(runtime.selectPublicationItems(manifest, items, new Date('2026-08-15T19:00:00Z'))[0].id, 1);
});

test('browser runtime loads the manifest and index without a generated selection', async () => {
  const responses = new Map([
    ['https://example.test/collections/daily/collection.json', {
      ...manifest, id: 'daily', dataFile: 'items/index.json'
    }],
    ['https://example.test/collections/daily/items/index.json', [
      { id: 6, slot: 6, status: 'Published', dateFirstDisplayed: null, displayAfter: [], title: 'Saturday' }
    ]]
  ]);
  const loaded = await runtime.loadCollection('/collections/daily/collection.json', {
    baseUrl: 'https://example.test/',
    now: new Date('2026-08-15T19:00:00Z'),
    fetchImpl: async url => ({ ok: true, async json() { return responses.get(String(url)); } })
  });
  assert.equal(loaded.selectedItems[0].title, 'Saturday');
  assert.equal(loaded.selectionDate, '2026-08-15');
});

test('browser runtime accepts test_date only from a development HTTP host', () => {
  const originalLocation = globalThis.location;
  try {
    globalThis.location = new URL('https://reviewnudge-dev.localtest.me/login?test_date=2026-08-17');
    assert.equal(runtime.browserSelectionClock({}), '2026-08-17');
    globalThis.location = new URL('https://reviewnudge.etal.solutions/login?test_date=2026-08-17');
    assert.ok(runtime.browserSelectionClock({}) instanceof Date);
    globalThis.location = new URL('capacitor://localhost/login?test_date=2026-08-17');
    assert.ok(runtime.browserSelectionClock({}) instanceof Date);
  } finally {
    if (originalLocation === undefined) delete globalThis.location;
    else globalThis.location = originalLocation;
  }
});

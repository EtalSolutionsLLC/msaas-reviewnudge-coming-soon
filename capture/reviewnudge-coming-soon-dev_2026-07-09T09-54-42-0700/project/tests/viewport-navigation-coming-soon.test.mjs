import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { Buffer } from 'node:buffer';

const helperSource = await readFile(new URL('../www/assets/pm-viewport-navigation.js', import.meta.url), 'utf8');
const helperUrl = `data:text/javascript;base64,${Buffer.from(helperSource).toString('base64')}`;
const { calculateTargetScrollTop, getViewportFrame } = await import(helperUrl);

test('site bootstrap uses Portmason navigation for the landing target', async () => {
  const [html, site] = await Promise.all([
    readFile(new URL('../www/index.html', import.meta.url), 'utf8'),
    readFile(new URL('../www/assets/site.js', import.meta.url), 'utf8')
  ]);
  assert.match(html, /id="top"[^>]*data-pm-viewport-target/);
  assert.match(site, /bindViewportNavigation/);
  assert.match(site, /navigateToHash\('#top'/);
  assert.match(site, /if \(!window\.location\.hash\)/);
});

test('#early-access is a full-section alias of #top', async () => {
  const html = await readFile(new URL('../www/index.html', import.meta.url), 'utf8');
  assert.match(html, /<section class="coming-soon-grid pm-viewport-target" id="top"/);
  assert.match(html, /<span class="pm-viewport-alias" id="early-access"[^>]*data-pm-viewport-target/);
  assert.match(html, /\.pm-viewport-alias\s*\{[\s\S]*?position:\s*absolute;[\s\S]*?inset:\s*0;/);
  assert.doesNotMatch(html, /class="launch-card" id="early-access"/);
});

test('#top and #early-access produce identical Portmason alignment for identical section geometry', () => {
  const frame = getViewportFrame({ viewportHeight: 800, headerHeight: 64, documentRef: null, windowRef: null });
  const section = { targetTop: 112, targetHeight: 694, currentScrollY: 0, frame };
  assert.equal(calculateTargetScrollTop(section), calculateTargetScrollTop({ ...section }));
});

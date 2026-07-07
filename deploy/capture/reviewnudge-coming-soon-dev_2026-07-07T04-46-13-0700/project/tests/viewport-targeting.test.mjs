import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { Buffer } from 'node:buffer';

const htmlPath = new URL('../www/index.html', import.meta.url);
const helperPath = new URL('../www/assets/pm-viewport-navigation.js', import.meta.url);

test('viewport navigation helper is present and imported by the static page', async () => {
  assert.equal(existsSync(helperPath), true, 'www/assets/pm-viewport-navigation.js is required');
  const html = await readFile(htmlPath, 'utf8');
  assert.match(html, /import\s+\{\s*bindViewportNavigation\s*\}\s+from\s+["']\.\/assets\/pm-viewport-navigation\.js["']/);
  assert.match(html, /bindViewportNavigation\(document,\s*\{[\s\S]*headerSelector:\s*["']\[data-pm-sticky-header\]["']/);
});

test('updates and preview are sibling viewport targets, not nested targets', async () => {
  const html = await readFile(htmlPath, 'utf8');
  const updatesStart = html.indexOf('id="updates"');
  const previewStart = html.indexOf('id="preview"');
  assert.ok(updatesStart > -1, '#updates exists');
  assert.ok(previewStart > -1, '#preview exists');
  assert.ok(updatesStart < previewStart, '#updates appears before #preview');

  const between = html.slice(updatesStart, previewStart);
  const articleCount = (between.match(/<article class="mini-card">/g) || []).length;
  assert.equal(articleCount, 3, '#updates contains exactly the three mini cards before #preview starts');
  assert.match(html, /<section class="below-grid pm-viewport-target" id="updates"[\s\S]*?<\/section>\s*<section class="preview-frame pm-viewport-target" id="preview"/);
});

test('short viewport targets use the Portmason usable-viewport variable for centering surface', async () => {
  const html = await readFile(htmlPath, 'utf8');
  assert.match(html, /\.pm-viewport-target\s*\{[\s\S]*min-height:\s*var\(--pm-usable-vh,\s*auto\)/);
  assert.match(html, /\.pm-viewport-target\s*\{[\s\S]*align-content:\s*center/);
  assert.match(html, /id="updates"[^>]*data-pm-viewport-target/);
  assert.match(html, /id="preview"[^>]*data-pm-viewport-target/);
});

test('Portmason targeting math centers short sections and top-aligns tall sections', async () => {
  const helperSource = await readFile(helperPath, 'utf8');
  const helperUrl = `data:text/javascript;base64,${Buffer.from(helperSource).toString('base64')}`;
  const { getViewportFrame, calculateTargetScrollTop } = await import(helperUrl);

  const frame = getViewportFrame({ viewportHeight: 900, headerHeight: 72 });
  assert.equal(frame.usableHeight, 828);

  const shortTop = calculateTargetScrollTop({
    targetTop: 1200,
    targetHeight: 240,
    currentScrollY: 0,
    frame
  });
  assert.equal(shortTop, 834);

  const tallTop = calculateTargetScrollTop({
    targetTop: 1200,
    targetHeight: 900,
    currentScrollY: 0,
    frame
  });
  assert.equal(tallTop, 1128);
});

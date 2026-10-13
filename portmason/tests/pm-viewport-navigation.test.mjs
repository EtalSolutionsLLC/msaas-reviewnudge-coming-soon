import test from 'node:test';
import assert from 'node:assert/strict';
import {
  calculateTargetScrollTop,
  getViewportFrame
} from '../web/pm-viewport-navigation.js';

test('centers a section in the viewport below the sticky header', () => {
  const frame = getViewportFrame({ viewportHeight: 755, headerHeight: 60 });
  const top = calculateTargetScrollTop({
    targetTop: 900,
    targetHeight: 420,
    currentScrollY: 0,
    frame
  });
  assert.equal(frame.usableHeight, 695);
  assert.equal(top, 703);
});

test('top-aligns content taller than the usable viewport', () => {
  const frame = getViewportFrame({ viewportHeight: 755, headerHeight: 60 });
  const top = calculateTargetScrollTop({
    targetTop: 900,
    targetHeight: 800,
    currentScrollY: 0,
    frame
  });
  assert.equal(top, 840);
});

test('never scrolls above the document start', () => {
  const frame = getViewportFrame({ viewportHeight: 755, headerHeight: 60 });
  const top = calculateTargetScrollTop({
    targetTop: 10,
    targetHeight: 300,
    currentScrollY: 0,
    frame
  });
  assert.equal(top, 0);
});

import test from 'node:test';
import assert from 'node:assert/strict';

import { normalizePmDialogOptions } from '../web/templates/pmt-dialog.js';

test('Portmason confirmation dialog has concise safe defaults', () => {
  assert.deepEqual(normalizePmDialogOptions(' Continue? '), {
    message: 'Continue?',
    confirmLabel: 'Continue',
    cancelLabel: 'Cancel',
    tone: 'default'
  });
});

test('Portmason confirmation dialog accepts localized labels and danger tone', () => {
  assert.deepEqual(normalizePmDialogOptions('Delete this?', {
    confirmLabel: 'Delete',
    cancelLabel: 'Never mind',
    tone: 'danger'
  }), {
    message: 'Delete this?',
    confirmLabel: 'Delete',
    cancelLabel: 'Never mind',
    tone: 'danger'
  });
});

test('Portmason confirmation dialog rejects empty messages and unknown tones', () => {
  assert.throws(() => normalizePmDialogOptions('  '), /requires a message/);
  assert.equal(normalizePmDialogOptions('Continue?', { tone: 'warning' }).tone, 'default');
});

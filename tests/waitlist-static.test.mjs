import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const index = readFileSync('www/index.html', 'utf8');
const site = readFileSync('www/assets/site.js', 'utf8');
const js = readFileSync('www/assets/waitlist.js', 'utf8');
const config = readFileSync('www/assets/waitlist-config.js', 'utf8');
const gas = readFileSync('apps-script/Code.gs', 'utf8');

test('waitlist assets use static-root-relative paths and module bootstrap', () => {
  assert.match(index, /src="\.\/assets\/waitlist-config\.js"/);
  assert.match(index, /type="module" src="\.\/assets\/site\.js"/);
  assert.match(site, /import \{ bindWaitlist \} from '\.\/waitlist\.js'/);
  assert.doesNotMatch(index, /\/www\/assets/);
});

test('waitlist frontend posts without depending on readable CORS response', () => {
  assert.match(config, /REVIEWNUDGE_WAITLIST_ENDPOINT/);
  assert.match(js, /mode:\s*'no-cors'/);
  assert.match(js, /source:\s*'reviewnudge-coming-soon'/);
  assert.match(js, /traceId/);
});

test('waitlist frontend verifies the exact spreadsheet write through JSONP', () => {
  assert.match(js, /action:\s*'status'/);
  assert.match(js, /callback:\s*callbackName/);
  assert.match(js, /slice\(0, 16\)/);
  assert.match(js, /pollForRecordedRow/);
  assert.match(js, /response\.recorded/);
  assert.match(js, /submission_confirmed/);
});

test('apps script writes traceable waitlist and audit columns', () => {
  for (const column of ['received_at', 'email', 'source', 'page', 'referrer', 'user_agent', 'submitted_at_client', 'trace_id']) {
    assert.match(gas, new RegExp(column));
  }
  for (const auditColumn of ['recorded_at', 'trace_id', 'event', 'ok', 'waitlist_sheet', 'waitlist_row', 'email_hash', 'detail']) {
    assert.match(gas, new RegExp(auditColumn));
  }
});

test('apps script flushes and verifies the row before reporting success', () => {
  assert.match(gas, /SpreadsheetApp\.flush\(\)/);
  assert.match(gas, /rowVerified/);
  assert.match(gas, /row_verification_failed/);
  assert.match(gas, /row_recorded/);
  assert.match(gas, /findTraceRow_/);
});

test('public coming-soon assets do not expose a Slack webhook', () => {
  assert.doesNotMatch(index, /hooks\.slack\.com/i);
  assert.doesNotMatch(js, /hooks\.slack\.com/i);
  assert.doesNotMatch(config, /hooks\.slack\.com/i);
});


test('waitlist rejects duplicate normalized email addresses and reports the existing registration', () => {
  assert.match(gas, /findEmailRow_\(sheet, email\)/);
  assert.match(gas, /normalizeEmail_\(values\[i\]\[0\]\) === email/);
  assert.match(gas, /email_already_registered/);
  assert.match(gas, /duplicate write was skipped/);
  assert.match(js, /notifications\.waitlist\.alreadyRegistered/);
});

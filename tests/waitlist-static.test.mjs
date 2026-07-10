import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const index = readFileSync('www/index.html', 'utf8');
const site = readFileSync('www/assets/site.js', 'utf8');
const js = readFileSync('www/assets/waitlist.js', 'utf8');
const config = readFileSync('www/assets/waitlist-config.js', 'utf8');
const gas = readFileSync('apps-script/Code.gs', 'utf8');
const readme = readFileSync('README.md', 'utf8');

test('waitlist assets use static-root-relative paths and module bootstrap', () => {
  assert.match(index, /src="\.\/assets\/waitlist-config\.js"/);
  assert.match(index, /type="module" src="\.\/assets\/site\.js"/);
  assert.match(site, /import \{ bindWaitlist \} from '\.\/waitlist\.js'/);
  assert.doesNotMatch(index, /\/www\/assets/);
});

test('waitlist frontend submits one JSONP subscribe request with traceable metadata', () => {
  assert.match(config, /REVIEWNUDGE_WAITLIST_ENDPOINT/);
  assert.match(js, /action:\s*'subscribe'/);
  assert.match(js, /source:\s*'reviewnudge-coming-soon'/);
  assert.match(js, /traceId/);
  assert.match(js, /callback:\s*callbackName/);
  assert.match(js, /root\.head\.appendChild\(script\)/);
  assert.match(js, /JSONP_TIMEOUT_MS/);

  assert.doesNotMatch(js, /mode:\s*'no-cors'/);
  assert.doesNotMatch(js, /pollForRecordedRow/);
  assert.doesNotMatch(js, /action:\s*'status'/);
});

test('waitlist frontend trusts success only after the JSONP response confirms the saved row', () => {
  assert.match(js, /result\.ok !== true \|\| result\.recorded !== true/);
  assert.match(js, /submission_confirmed/);
  assert.match(js, /result\.state === 'email_already_registered'/);
  assert.match(js, /notifications\.waitlist\.alreadyRegistered/);
  assert.match(js, /form\.reset\(\)/);
  assert.match(js, /delete windowRef\[callbackName\]/);
});

test('apps script exposes single-request JSONP subscription and keeps status lookup for older clients', () => {
  assert.match(gas, /if \(action === 'subscribe'\)/);
  assert.match(gas, /output_\(processSubscription_\(e\.parameter \|\| \{\}, 'JSONP'\), e\)/);
  assert.match(gas, /if \(action === 'status'\)/);
  assert.match(gas, /singleRequestSubscription:\s*true/);
  assert.match(gas, /callback \+ '\(' \+ JSON\.stringify\(payload\) \+ '\);'/);
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

test('README documents the current one-request JSONP contract', () => {
  assert.match(readme, /one JSONP request/i);
  assert.match(readme, /validates, deduplicates, writes, verifies/i);
  assert.doesNotMatch(readme, /mode=no-cors/i);
  assert.doesNotMatch(readme, /polls the status endpoint/i);
});

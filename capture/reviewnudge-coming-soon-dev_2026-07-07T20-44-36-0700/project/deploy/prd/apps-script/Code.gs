/**
 * ReviewNudge Coming Soon waitlist endpoint.
 * Deploy as a Google Apps Script Web App and point
 * www/assets/waitlist-config.js at the Web App URL.
 *
 * Script Properties:
 *   SHEET_ID   Required. Target Google Sheet ID.
 *   SHEET_NAME Optional. Defaults to "Waitlist".
 */
function doPost(e) {
  var lock = LockService.getScriptLock();
  lock.waitLock(10000);

  try {
    var props = PropertiesService.getScriptProperties();
    var sheetId = props.getProperty('SHEET_ID');
    var sheetName = props.getProperty('SHEET_NAME') || 'Waitlist';

    if (!sheetId) {
      return json_({ ok: false, error: 'SHEET_ID is not configured.' });
    }

    var payload = parsePayload_(e);
    var email = normalizeEmail_(payload.email);

    if (!email) {
      return json_({ ok: false, error: 'A valid email address is required.' });
    }

    var spreadsheet = SpreadsheetApp.openById(sheetId);
    var sheet = spreadsheet.getSheetByName(sheetName) || spreadsheet.insertSheet(sheetName);
    ensureHeader_(sheet);

    sheet.appendRow([
      new Date(),
      email,
      payload.source || '',
      payload.page || '',
      payload.referrer || '',
      payload.userAgent || '',
      payload.submittedAt || ''
    ]);

    return json_({ ok: true });
  } catch (err) {
    return json_({ ok: false, error: String(err && err.message ? err.message : err) });
  } finally {
    lock.releaseLock();
  }
}

function doGet() {
  return json_({ ok: true, service: 'reviewnudge-waitlist' });
}

function parsePayload_(e) {
  if (!e || !e.postData || !e.postData.contents) return {};
  try {
    return JSON.parse(e.postData.contents);
  } catch (err) {
    return {};
  }
}

function normalizeEmail_(value) {
  var email = String(value || '').trim().toLowerCase();
  var ok = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
  return ok ? email : '';
}

function ensureHeader_(sheet) {
  if (sheet.getLastRow() > 0) return;
  sheet.appendRow([
    'received_at',
    'email',
    'source',
    'page',
    'referrer',
    'user_agent',
    'submitted_at_client'
  ]);
}

function json_(payload) {
  return ContentService
    .createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}

/**
 * ReviewNudge Coming Soon waitlist endpoint.
 *
 * Deploy as a Google Apps Script Web App and point
 * www/assets/waitlist-config.js at the Web App URL.
 *
 * Script Properties:
 *   SHEET_ID        Required. Target Google Sheet ID.
 *   SHEET_NAME      Optional. Defaults to "Waitlist".
 *   AUDIT_SHEET_NAME Optional. Defaults to "WaitlistAudit".
 *
 * The public page submits with mode=no-cors, so the browser cannot read the
 * POST response. Each request therefore carries a trace ID. The browser polls
 * doGet?action=status&traceId=... through JSONP until this script confirms that
 * the exact row exists in the spreadsheet.
 */

var WAITLIST_HEADERS = [
  'received_at',
  'email',
  'source',
  'page',
  'referrer',
  'user_agent',
  'submitted_at_client',
  'trace_id'
];

var AUDIT_HEADERS = [
  'recorded_at',
  'trace_id',
  'event',
  'ok',
  'waitlist_sheet',
  'waitlist_row',
  'email_hash',
  'source',
  'detail'
];

function doPost(e) {
  var payload = parsePayload_(e);
  var traceId = normalizeTraceId_(payload.traceId) || Utilities.getUuid();
  var email = normalizeEmail_(payload.email);
  var source = safeText_(payload.source, 120) || 'reviewnudge-coming-soon';
  var emailHash = email ? hashText_(email) : '';
  var lock = LockService.getScriptLock();
  var lockAcquired = false;
  var spreadsheet = null;
  var sheetName = '';

  logEvent_('request_received', true, {
    traceId: traceId,
    source: source,
    emailHash: emailHash,
    contentLength: e && e.postData ? e.postData.length : 0
  });

  try {
    var props = PropertiesService.getScriptProperties();
    var sheetId = props.getProperty('SHEET_ID');
    sheetName = props.getProperty('SHEET_NAME') || 'Waitlist';

    if (!sheetId) {
      logEvent_('configuration_failed', false, {
        traceId: traceId,
        detail: 'SHEET_ID is not configured.'
      });
      return json_({
        ok: false,
        traceId: traceId,
        state: 'configuration_failed',
        error: 'SHEET_ID is not configured.'
      });
    }

    lock.waitLock(15000);
    lockAcquired = true;

    spreadsheet = SpreadsheetApp.openById(sheetId);
    safeAudit_(spreadsheet, props, {
      traceId: traceId,
      event: 'request_received',
      ok: true,
      waitlistSheet: sheetName,
      waitlistRow: '',
      emailHash: emailHash,
      source: source,
      detail: 'POST accepted by Apps Script.'
    });

    if (!email) {
      safeAudit_(spreadsheet, props, {
        traceId: traceId,
        event: 'validation_failed',
        ok: false,
        waitlistSheet: sheetName,
        waitlistRow: '',
        emailHash: '',
        source: source,
        detail: 'A valid email address is required.'
      });
      return json_({
        ok: false,
        traceId: traceId,
        state: 'validation_failed',
        error: 'A valid email address is required.'
      });
    }

    var sheet = spreadsheet.getSheetByName(sheetName) || spreadsheet.insertSheet(sheetName);
    ensureHeader_(sheet, WAITLIST_HEADERS);

    var existingRow = findTraceRow_(sheet, traceId);
    if (existingRow) {
      safeAudit_(spreadsheet, props, {
        traceId: traceId,
        event: 'duplicate_confirmed',
        ok: true,
        waitlistSheet: sheetName,
        waitlistRow: existingRow,
        emailHash: emailHash,
        source: source,
        detail: 'Trace ID already exists; duplicate write was skipped.'
      });
      return json_({
        ok: true,
        traceId: traceId,
        state: 'duplicate_confirmed',
        recorded: true,
        row: existingRow
      });
    }

    var targetRow = Math.max(sheet.getLastRow() + 1, 2);
    var receivedAt = new Date();
    var values = [[
      receivedAt,
      email,
      source,
      safeText_(payload.page, 1000),
      safeText_(payload.referrer, 1000),
      safeText_(payload.userAgent, 1000),
      safeText_(payload.submittedAt, 120),
      traceId
    ]];

    sheet.getRange(targetRow, 1, 1, WAITLIST_HEADERS.length).setValues(values);
    SpreadsheetApp.flush();

    var saved = sheet.getRange(targetRow, 1, 1, WAITLIST_HEADERS.length).getValues()[0];
    var rowVerified = normalizeEmail_(saved[1]) === email && String(saved[7] || '') === traceId;

    if (!rowVerified) {
      safeAudit_(spreadsheet, props, {
        traceId: traceId,
        event: 'row_verification_failed',
        ok: false,
        waitlistSheet: sheetName,
        waitlistRow: targetRow,
        emailHash: emailHash,
        source: source,
        detail: 'The write completed but the saved row did not match the submitted email hash and trace ID.'
      });
      return json_({
        ok: false,
        traceId: traceId,
        state: 'row_verification_failed',
        recorded: false,
        error: 'The spreadsheet row could not be verified.'
      });
    }

    safeAudit_(spreadsheet, props, {
      traceId: traceId,
      event: 'row_recorded',
      ok: true,
      waitlistSheet: sheetName,
      waitlistRow: targetRow,
      emailHash: emailHash,
      source: source,
      detail: 'Waitlist row written and verified.'
    });

    logEvent_('row_recorded', true, {
      traceId: traceId,
      sheetName: sheetName,
      row: targetRow,
      emailHash: emailHash
    });

    return json_({
      ok: true,
      traceId: traceId,
      state: 'row_recorded',
      recorded: true,
      row: targetRow
    });
  } catch (err) {
    var detail = compactError_(err);

    logEvent_('exception', false, {
      traceId: traceId,
      sheetName: sheetName,
      emailHash: emailHash,
      detail: detail
    });

    if (spreadsheet) {
      try {
        safeAudit_(spreadsheet, PropertiesService.getScriptProperties(), {
          traceId: traceId,
          event: 'exception',
          ok: false,
          waitlistSheet: sheetName,
          waitlistRow: '',
          emailHash: emailHash,
          source: source,
          detail: detail
        });
      } catch (auditErr) {
        console.error(JSON.stringify({
          service: 'reviewnudge-waitlist',
          event: 'audit_exception',
          traceId: traceId,
          detail: compactError_(auditErr)
        }));
      }
    }

    return json_({
      ok: false,
      traceId: traceId,
      state: 'exception',
      recorded: false,
      error: detail
    });
  } finally {
    if (lockAcquired) {
      lock.releaseLock();
    }
  }
}

function doGet(e) {
  var action = e && e.parameter ? String(e.parameter.action || '') : '';

  if (action === 'status') {
    return statusResponse_(e);
  }

  return output_({
    ok: true,
    service: 'reviewnudge-waitlist',
    audit: true,
    verification: true,
    checkedAt: new Date().toISOString()
  }, e);
}

function statusResponse_(e) {
  var traceId = normalizeTraceId_(e && e.parameter ? e.parameter.traceId : '');

  if (!traceId) {
    return output_({
      ok: false,
      recorded: false,
      state: 'invalid_trace_id',
      error: 'A valid traceId is required.'
    }, e);
  }

  try {
    var props = PropertiesService.getScriptProperties();
    var sheetId = props.getProperty('SHEET_ID');
    var sheetName = props.getProperty('SHEET_NAME') || 'Waitlist';

    if (!sheetId) {
      return output_({
        ok: false,
        traceId: traceId,
        recorded: false,
        state: 'configuration_failed',
        error: 'SHEET_ID is not configured.'
      }, e);
    }

    var spreadsheet = SpreadsheetApp.openById(sheetId);
    var sheet = spreadsheet.getSheetByName(sheetName);
    var row = sheet ? findTraceRow_(sheet, traceId) : 0;
    var latestAudit = findLatestAudit_(spreadsheet, props, traceId);
    var state = row ? 'row_recorded' : (latestAudit.event || 'pending');
    var failed = !row && /(?:failed|exception)$/.test(state);

    return output_({
      ok: !failed,
      traceId: traceId,
      recorded: Boolean(row),
      row: row || null,
      state: state,
      detail: latestAudit.detail || '',
      checkedAt: new Date().toISOString()
    }, e);
  } catch (err) {
    return output_({
      ok: false,
      traceId: traceId,
      recorded: false,
      state: 'status_exception',
      error: compactError_(err),
      checkedAt: new Date().toISOString()
    }, e);
  }
}

function parsePayload_(e) {
  if (!e || !e.postData || !e.postData.contents) return {};

  try {
    return JSON.parse(e.postData.contents);
  } catch (err) {
    logEvent_('payload_parse_failed', false, { detail: compactError_(err) });
    return {};
  }
}

function normalizeEmail_(value) {
  var email = String(value || '').trim().toLowerCase();
  var ok = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
  return ok ? email : '';
}

function normalizeTraceId_(value) {
  var traceId = String(value || '').trim();
  return /^[A-Za-z0-9_-]{8,128}$/.test(traceId) ? traceId : '';
}

function safeText_(value, maxLength) {
  var text = String(value || '');
  return text.length > maxLength ? text.slice(0, maxLength) : text;
}

function ensureHeader_(sheet, headers) {
  var current = sheet.getRange(1, 1, 1, headers.length).getValues()[0];
  var differs = false;

  for (var i = 0; i < headers.length; i += 1) {
    if (String(current[i] || '') !== headers[i]) {
      differs = true;
      break;
    }
  }

  if (differs) {
    sheet.getRange(1, 1, 1, headers.length).setValues([headers]);
    sheet.setFrozenRows(1);
  }
}

function findTraceRow_(sheet, traceId) {
  if (!sheet || sheet.getLastRow() < 2) return 0;

  var traceColumn = WAITLIST_HEADERS.indexOf('trace_id') + 1;
  var range = sheet.getRange(2, traceColumn, sheet.getLastRow() - 1, 1);
  var match = range.createTextFinder(traceId).matchEntireCell(true).findNext();
  return match ? match.getRow() : 0;
}

function safeAudit_(spreadsheet, props, record) {
  try {
    var auditSheetName = props.getProperty('AUDIT_SHEET_NAME') || 'WaitlistAudit';
    var auditSheet = spreadsheet.getSheetByName(auditSheetName) || spreadsheet.insertSheet(auditSheetName);
    ensureHeader_(auditSheet, AUDIT_HEADERS);

    var row = Math.max(auditSheet.getLastRow() + 1, 2);
    auditSheet.getRange(row, 1, 1, AUDIT_HEADERS.length).setValues([[
      new Date(),
      record.traceId || '',
      record.event || '',
      Boolean(record.ok),
      record.waitlistSheet || '',
      record.waitlistRow || '',
      record.emailHash || '',
      record.source || '',
      safeText_(record.detail, 1000)
    ]]);
    SpreadsheetApp.flush();

    logEvent_(record.event || 'audit', Boolean(record.ok), {
      traceId: record.traceId || '',
      waitlistSheet: record.waitlistSheet || '',
      waitlistRow: record.waitlistRow || '',
      emailHash: record.emailHash || '',
      source: record.source || '',
      detail: record.detail || ''
    });
  } catch (err) {
    console.error(JSON.stringify({
      service: 'reviewnudge-waitlist',
      event: 'audit_write_failed',
      traceId: record.traceId || '',
      detail: compactError_(err)
    }));
  }
}

function findLatestAudit_(spreadsheet, props, traceId) {
  var auditSheetName = props.getProperty('AUDIT_SHEET_NAME') || 'WaitlistAudit';
  var auditSheet = spreadsheet.getSheetByName(auditSheetName);

  if (!auditSheet || auditSheet.getLastRow() < 2) {
    return { event: '', detail: '' };
  }

  var values = auditSheet
    .getRange(2, 1, auditSheet.getLastRow() - 1, AUDIT_HEADERS.length)
    .getValues();

  for (var i = values.length - 1; i >= 0; i -= 1) {
    if (String(values[i][1] || '') === traceId) {
      return {
        event: String(values[i][2] || ''),
        detail: String(values[i][8] || '')
      };
    }
  }

  return { event: '', detail: '' };
}

function hashText_(value) {
  var bytes = Utilities.computeDigest(
    Utilities.DigestAlgorithm.SHA_256,
    String(value || ''),
    Utilities.Charset.UTF_8
  );

  return bytes.map(function (byte) {
    var normalized = byte < 0 ? byte + 256 : byte;
    return ('0' + normalized.toString(16)).slice(-2);
  }).join('');
}

function compactError_(err) {
  var message = err && err.message ? err.message : err;
  return safeText_(message || 'Unknown error', 1000);
}

function logEvent_(event, ok, fields) {
  var payload = fields || {};
  payload.service = 'reviewnudge-waitlist';
  payload.event = event;
  payload.ok = Boolean(ok);
  payload.timestamp = new Date().toISOString();

  if (ok) {
    console.log(JSON.stringify(payload));
  } else {
    console.error(JSON.stringify(payload));
  }
}

function output_(payload, e) {
  var callback = normalizeCallback_(e && e.parameter ? e.parameter.callback : '');

  if (callback) {
    return ContentService
      .createTextOutput(callback + '(' + JSON.stringify(payload) + ');')
      .setMimeType(ContentService.MimeType.JAVASCRIPT);
  }

  return json_(payload);
}

function normalizeCallback_(value) {
  var callback = String(value || '').trim();
  return /^[A-Za-z_$][A-Za-z0-9_$]{0,63}$/.test(callback) ? callback : '';
}

function json_(payload) {
  return ContentService
    .createTextOutput(JSON.stringify(payload))
    .setMimeType(ContentService.MimeType.JSON);
}

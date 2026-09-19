/**
 * Spend — Gmail sync (Google Apps Script).
 *
 * Runs inside ONE Gmail account. Every 15 minutes it reads receipt and
 * bank-alert emails (see GMAIL_QUERY in Parsers.js), turns them into
 * purchases, and keeps them in a private Google Sheet. The Spend app fetches
 * them with a POST that carries a secret key, so the key never sits in a URL.
 *
 * One-time setup (see README.md): paste Parsers.js and this file, fill in
 * CARD_MAP below, run setup(), then Deploy → Web app.
 *
 * The script only READS Gmail. It never sends, labels, moves or deletes mail.
 */

/** Last 4 digits of each card -> Spend card id. Edit to match your cards. */
var CARD_MAP = {
  // '1234': 'nab',
};

var LOOKBACK_DAYS = 120;
var SHEET_NAME = 'Purchases';
var HEADERS = ['id', 'kind', 'merchant', 'rawMerchant', 'platform', 'amount', 'currency', 'card', 'date', 'note', 'subscription', 'messageId', 'last4'];

/** Run once by hand. Creates the sheet, the secret key and the 15-minute timer. */
function setup() {
  var props = PropertiesService.getScriptProperties();
  if (!props.getProperty('SECRET')) {
    props.setProperty('SECRET', Utilities.getUuid() + Utilities.getUuid().slice(0, 8));
  }
  sheet_();
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === 'sync') ScriptApp.deleteTrigger(t);
  });
  ScriptApp.newTrigger('sync').timeBased().everyMinutes(15).create();
  sync();
  Logger.log('Setup done. Your secret key (paste it into Spend → Settings → Email Receipts):');
  Logger.log(props.getProperty('SECRET'));
}

/** Reads new matching emails and stores any purchases found. Safe to run often. */
function sync() {
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(20000)) return;
  try {
    var sh = sheet_();
    var seen = seenMessageIds_(sh);
    var query = '(' + GMAIL_QUERY + ') newer_than:' + LOOKBACK_DAYS + 'd';
    var threads = GmailApp.search(query, 0, 200);
    var rows = [];

    threads.forEach(function (thread) {
      var messages = thread.getMessages();
      var previous = null; // message before this one in the thread

      messages.forEach(function (m) {
        var prev = previous;
        previous = m;
        if (seen[m.getId()]) return;
        var msg = { id: m.getId(), from: m.getFrom(), subject: m.getSubject(), body: m.getPlainBody(), date: m.getDate() };
        var records = parseEmail(msg, CARD_MAP);

        // DoorDash re-sends the confirmation when an order is adjusted. Gmail
        // threads it with the original, so it replaces the email just before
        // it (same thread, within a day). Repeat orders from the same
        // restaurant also share a thread, so everything else stays separate.
        var adjusted = /adjustments to your order/i.test(msg.body);
        if (adjusted && prev && records.length === 1 && m.getDate() - prev.getDate() < 24 * 3600 * 1000) {
          records[0].id = prev.getId() + '-0';
        }

        records.forEach(function (r) { r.messageId = m.getId(); rows.push(r); });
        if (!records.length) rows.push({ id: 'skip-' + m.getId(), kind: 'skip', messageId: m.getId() });
      });
    });

    upsert_(sh, rows);
  } finally {
    lock.releaseLock();
  }
}

/**
 * Web app entry. Body: {"key": "...", "since": "ISO date, optional"}.
 * Returns {"account", "generatedAt", "records": [...]}.
 */
function doPost(e) {
  var body = {};
  try { body = JSON.parse((e && e.postData && e.postData.contents) || '{}'); } catch (err) {}
  var secret = PropertiesService.getScriptProperties().getProperty('SECRET');
  if (!secret || body.key !== secret) return json_({ error: 'unauthorised' });

  var since = body.since ? new Date(body.since) : null;
  var records = readAll_(sheet_()).filter(function (r) {
    return r.kind !== 'skip' && (!since || new Date(r.date) >= since);
  });
  return json_({
    account: Session.getEffectiveUser().getEmail(),
    generatedAt: new Date().toISOString(),
    records: records,
  });
}

/** A plain GET only says the endpoint is alive; it never returns data. */
function doGet() {
  return json_({ ok: true, hint: 'POST {"key": ...} to read purchases' });
}

// MARK: - Sheet storage

function sheet_() {
  var props = PropertiesService.getScriptProperties();
  var id = props.getProperty('SHEET_ID');
  var ss = id ? SpreadsheetApp.openById(id) : null;
  if (!ss) {
    ss = SpreadsheetApp.create('Spend – email purchases (private)');
    props.setProperty('SHEET_ID', ss.getId());
  }
  var sh = ss.getSheetByName(SHEET_NAME) || ss.insertSheet(SHEET_NAME);
  if (sh.getLastRow() === 0) sh.appendRow(HEADERS);
  else if (sh.getLastColumn() < HEADERS.length) sh.getRange(1, 1, 1, HEADERS.length).setValues([HEADERS]); // new columns
  return sh;
}

function readAll_(sh) {
  var values = sh.getDataRange().getValues();
  var head = values.shift() || HEADERS;
  return values.map(function (row) {
    var r = {};
    head.forEach(function (h, i) { r[h] = row[i]; });
    r.amount = String(r.amount);
    r.date = r.date instanceof Date ? r.date.toISOString() : String(r.date);
    r.subscription = r.subscription ? JSON.parse(r.subscription) : null;
    r.platform = r.platform || null;
    r.last4 = r.last4 ? ('000' + String(r.last4)).slice(-4) : null;
    return r;
  });
}

/** Emails already turned into purchases. Skipped emails are retried each run,
 *  so a parser fix picks them up without resetting anything. */
function seenMessageIds_(sh) {
  var seen = {};
  readAll_(sh).forEach(function (r) { if (r.messageId && r.kind !== 'skip') seen[r.messageId] = true; });
  return seen;
}

/** Insert new rows; replace rows whose id already exists (DoorDash updates). */
function upsert_(sh, rows) {
  if (!rows.length) return;
  var ids = sh.getRange(1, 1, Math.max(1, sh.getLastRow()), 1).getValues().map(function (v) { return String(v[0]); });
  rows.forEach(function (r) {
    var line = HEADERS.map(function (h) {
      if (h === 'subscription') return r.subscription ? JSON.stringify(r.subscription) : '';
      if (h === 'amount') return "'" + (r.amount || ''); // keep as text, no float rounding
      if (h === 'last4') return r.last4 ? "'" + r.last4 : ''; // text, so 0123 stays 0123
      return r[h] === undefined || r[h] === null ? '' : r[h];
    });
    var at = ids.indexOf(String(r.id));
    if (at >= 0) sh.getRange(at + 1, 1, 1, HEADERS.length).setValues([line]);
    else { sh.appendRow(line); ids.push(String(r.id)); }
  });
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

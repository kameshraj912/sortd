/**
 * Spend — email parsers.
 *
 * Turns receipt and bank-alert emails into purchases for the Spend app.
 * Pure functions only (no Gmail calls), so the same file runs in Google Apps
 * Script and in Node for tests.
 *
 * parseEmail(msg, cardMap) -> array of records:
 *   { id, kind: 'purchase' | 'refund' | 'subscription', merchant, rawMerchant,
 *     platform, amount, currency, card, last4, date, note, subscription }
 *
 * msg     = { id, from, subject, body, date }   (date: JS Date the email arrived)
 * cardMap = { '1234': 'nab', ... }              last 4 digits -> Spend card id
 *
 * Formats come from Raj's real emails (Sep 2026). If a sender changes its
 * wording, the matching parser returns [] rather than guessing.
 */

var SGT_OFFSET = '+08:00';

var MONTHS = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11 };

/** Collapse table pipes, odd spaces and newlines into single spaces. */
function normalize(text) {
  return String(text || '')
    .replace(/\|/g, ' ')
    .replace(/[ ͏​‌ ⁠]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** "1,082.52" -> "1046.80" (kept as a string so no float rounding). */
function money(text) {
  return String(text).replace(/,/g, '');
}

/** "A$" / "S$" / "US$" / "$" / "AUD " -> ISO code. */
function currencyFrom(symbol, fallback) {
  var s = String(symbol || '').trim().toUpperCase();
  if (/^[A-Z]{3}$/.test(s)) return s;
  if (s === 'A$' || s === 'AU$') return 'AUD';
  if (s === 'S$') return 'SGD';
  if (s === 'US$') return 'USD';
  return fallback;
}

/** The digits themselves, sent so the app can match them to Raj's cards. */
function last4Of(last4) {
  return last4 && /^\d{4}$/.test(last4) ? last4 : null;
}

function cardFor(last4, cardMap) {
  return (last4 && cardMap && cardMap[last4]) || 'other';
}

/** "16-Sep-26" + "11:54 AM" in Singapore time -> ISO string. */
function sgtDate(dmy, time) {
  var d = /^(\d{1,2})-([A-Za-z]{3})-(\d{2})$/.exec(dmy);
  var t = /^(\d{1,2}):(\d{2})\s?([AP]M)$/i.exec(time.trim());
  if (!d || !t) return null;
  var hour = (Number(t[1]) % 12) + (t[3].toUpperCase() === 'PM' ? 12 : 0);
  var month = MONTHS[d[2].toLowerCase()];
  if (month === undefined) return null;
  var iso = '20' + d[3] + '-' + pad(month + 1) + '-' + pad(d[1]) + 'T' + pad(hour) + ':' + t[2] + ':00' + SGT_OFFSET;
  return new Date(iso).toISOString();
}

function pad(n) { return (Number(n) < 10 ? '0' : '') + Number(n); }

/** Bank descriptors -> readable name + delivery platform. */
function cleanDescriptor(raw) {
  var s = raw.split('~')[0].trim();
  var upper = s.toUpperCase();
  if (/^DD \*|DOORDASH/.test(upper)) return { merchant: 'DoorDash', platform: 'doordash' };
  if (/UBER\s*\*\s*EATS/.test(upper)) return { merchant: 'Uber Eats', platform: 'uber' };
  if (/^UBER\s*\*/.test(upper)) return { merchant: 'Uber', platform: 'uber' };
  return { merchant: s, platform: null };
}

// MARK: - Standard Chartered Singapore card alerts (alerts.sg@sc.com)

function parseStanChart(msg, cardMap) {
  var text = normalize(msg.body);
  var out = [];
  var buy = /charging \+?([A-Z]{3}) ([\d,]+\.\d{2}) to yr (debit|credit) card \*+(\d{4}) on (\d{2}-[A-Za-z]{3}-\d{2})\s*(\d{1,2}:\d{2}\s?[AP]M) at (.+?)\.\s+To modify/i;
  var back = /Transaction of \+?([A-Z]{3}) ([\d,]+\.\d{2}) made on your card \*+(\d{4}) on (\d{2}-[A-Za-z]{3}-\d{2})\s*(\d{1,2}:\d{2}\s?[AP]M) at (.+?) has been reversed/i;
  var m;
  if ((m = buy.exec(text))) {
    var d = cleanDescriptor(m[7]);
    out.push(record(msg, 0, {
      kind: 'purchase', merchant: d.merchant, rawMerchant: m[7], platform: d.platform,
      amount: money(m[2]), currency: m[1].toUpperCase(), card: cardFor(m[4], cardMap), last4: last4Of(m[4]),
      date: sgtDate(m[5], m[6]) || msg.date.toISOString(),
    }));
  } else if ((m = back.exec(text))) {
    var r = cleanDescriptor(m[6]);
    out.push(record(msg, 0, {
      kind: 'refund', merchant: r.merchant, rawMerchant: m[6], platform: r.platform,
      amount: money(m[2]), currency: m[1].toUpperCase(), card: cardFor(m[3], cardMap), last4: last4Of(m[3]),
      date: sgtDate(m[4], m[5]) || msg.date.toISOString(), note: 'Reversed by the bank',
    }));
  }
  return out;
}

// MARK: - DoorDash order confirmations (no-reply@doordash.com)

function parseDoorDash(msg) {
  var subject = /Order Confirmation for .+? from (.+)$/i.exec(msg.subject || '');
  if (!subject) return [];
  var text = normalize(msg.body);
  var total = /Total Charged \$([\d,]+\.\d{2})/i.exec(text) || /Total: \$([\d,]+\.\d{2})/i.exec(text);
  if (!total) return [];
  var restaurant = subject[1].trim();
  var adjusted = /adjustments to your order/i.test(text);
  return [record(msg, 0, {
    kind: 'purchase', merchant: restaurant, rawMerchant: 'DoorDash: ' + restaurant, platform: 'doordash',
    amount: money(total[1]), currency: 'AUD', card: 'other', date: msg.date.toISOString(),
    note: (/Paid with Apple Pay/i.test(text) ? 'DoorDash · paid with Apple Pay' : 'DoorDash') + (adjusted ? ' · order adjusted' : ''),
  })];
}

// MARK: - Apple tax invoices / receipts (no_reply@email.apple.com)

function parseApple(msg, cardMap) {
  if (!/tax invoice|receipt from apple/i.test(msg.subject || '')) return [];
  var text = normalize(msg.body);
  var item = /Apple Account: \S+ (.+?) (?:Renews (\d{1,2} [A-Za-z]+ \d{4}) )?\$([\d,]+\.\d{2})/.exec(text);
  var paid = /(?:Visa|Mastercard|Amex|American Express)\s*[•·.]+\s*(\d{4})\s+\$([\d,]+\.\d{2})/i.exec(text);
  if (!item) return parseAppleInApp(msg, text, cardMap);
  var title = item[1].trim();
  var app = title.split(':')[0].trim();
  var period = /annual|year/i.test(title) ? 'yearly' : /month/i.test(title) ? 'monthly' : null;
  return [record(msg, 0, {
    kind: 'purchase', merchant: app, rawMerchant: 'Apple: ' + title, platform: 'apple',
    amount: money(paid ? paid[2] : item[3]), currency: 'AUD',
    card: cardFor(paid && paid[1], cardMap), last4: last4Of(paid && paid[1]), date: msg.date.toISOString(),
    note: 'App Store · ' + title,
    subscription: item[2] || period ? { name: app, period: period, renews: item[2] || null } : null,
  })];
}

/**
 * Older invoice layout, used for in-app purchases:
 * "BILLED TO Visa .... 1234 … App Store Some App: Tagline 3 Boosts In-App Purchase … TOTAL $39.99"
 */
function parseAppleInApp(msg, text, cardMap) {
  var total = /TOTAL \$([\d,]+\.\d{2})/.exec(text);
  var item = /App Store (.+?) (?:In-App Purchase|Report a Problem|\$)/.exec(text);
  if (!total || !item) return [];
  var card = /(?:Visa|Mastercard|Amex|American Express)\s*[•·.]{2,}\s*(\d{4})/i.exec(text);
  var title = item[1].trim();
  var inApp = /In-App Purchase/i.test(text);
  return [record(msg, 0, {
    kind: 'purchase', merchant: title.split(':')[0].trim(), rawMerchant: 'Apple: ' + title, platform: 'apple',
    amount: money(total[1]), currency: 'AUD', card: cardFor(card && card[1], cardMap), last4: last4Of(card && card[1]),
    date: msg.date.toISOString(), note: 'App Store · ' + title + (inApp ? ' · in-app purchase' : ''),
  })];
}

// MARK: - YouTrip daily summaries (noreply@you.co)

function parseYouTrip(msg) {
  if (!/Summary of your recent online purchases/i.test(msg.subject || '')) return [];
  var text = normalize(msg.body);
  // Gmail's plain text may bold the header: "(UTC+8)*." — allow the asterisk.
  var row = /(?:\(UTC\+8\)\*?\s?\.|[AP]M)\s+(.+?)\s+([A-Z]{3}) ([\d,]+\.\d{2})\s+Ref\. No: (\S+)\s+(\d{1,2}:\d{2}\s?[AP]M)/g;
  var out = [];
  var m;
  var i = 0;
  while ((m = row.exec(text))) {
    var d = cleanDescriptor(m[1]);
    out.push(record(msg, i++, {
      kind: 'purchase', merchant: d.merchant, rawMerchant: m[1].split('~')[0].trim(), platform: d.platform,
      amount: money(m[3]), currency: m[2], card: 'youtrip', date: youTripDate(msg.date, m[5]),
      note: 'YouTrip · ref ' + m[4],
    }));
    row.lastIndex = m.index + m[0].length - m[5].length; // let the time end the next row's lookbehind
  }
  return out;
}

/** Summary covers the last 24h in SGT; a time later than the email means yesterday. */
function youTripDate(sent, time) {
  var t = /^(\d{1,2}):(\d{2})\s?([AP]M)$/i.exec(time.trim());
  var sgt = new Date(sent.getTime() + 8 * 3600 * 1000); // shift so UTC fields read as SGT
  var hour = (Number(t[1]) % 12) + (t[3].toUpperCase() === 'PM' ? 12 : 0);
  var day = new Date(Date.UTC(sgt.getUTCFullYear(), sgt.getUTCMonth(), sgt.getUTCDate(), hour, Number(t[2])));
  if (day.getTime() > sgt.getTime()) day = new Date(day.getTime() - 24 * 3600 * 1000);
  return new Date(day.getTime() - 8 * 3600 * 1000).toISOString();
}

// MARK: - Stripe receipts and refunds (receipts+…@stripe.com, Anthropic invoices)

function parseStripe(msg, cardMap) {
  var text = normalize(msg.body);
  var fallback = 'AUD';
  var m;
  if ((m = /Refund from (.+?) Receipt #([\d-]+) Refunded ([A-Z]{0,2}\$|[A-Z]{3} ?)([\d,]+\.\d{2})/.exec(text))) {
    var to = /Refunded to - (\d{4})/.exec(text);
    return [record(msg, 0, {
      kind: 'refund', merchant: tidyCompany(m[1]), rawMerchant: m[1], platform: null,
      amount: money(m[4]), currency: currencyFrom(m[3], fallback), card: cardFor(to && to[1], cardMap), last4: last4Of(to && to[1]),
      date: msg.date.toISOString(), note: 'Refund · receipt #' + m[2],
    })];
  }
  if ((m = /Receipt from (.+?) Receipt #([\d-]+) Amount paid ([A-Z]{0,2}\$|[A-Z]{3} ?)([\d,]+\.\d{2})/.exec(text))) {
    var pm = /Payment method - (\d{4})/.exec(text);
    return [record(msg, 0, {
      kind: 'purchase', merchant: tidyCompany(m[1]), rawMerchant: m[1], platform: null,
      amount: money(m[4]), currency: currencyFrom(m[3], fallback), card: cardFor(pm && pm[1], cardMap), last4: last4Of(pm && pm[1]),
      date: msg.date.toISOString(), note: 'Receipt #' + m[2],
    })];
  }
  // Stripe invoice refund (e.g. Anthropic): "Refund from X S$2.48 Refunded on July 3, 2026 … Refunded to - 1234"
  if ((m = /Refund from (.+?) ([A-Z]{0,2}\$)([\d,]+\.\d{2}) Refunded on ([A-Za-z]+ \d{1,2}, \d{4})/.exec(text))) {
    var to2 = /Refunded to - (\d{4})/.exec(text);
    return [record(msg, 0, {
      kind: 'refund', merchant: tidyCompany(m[1]), rawMerchant: m[1], platform: null,
      amount: money(m[3]), currency: currencyFrom(m[2], fallback), card: cardFor(to2 && to2[1], cardMap), last4: last4Of(to2 && to2[1]),
      date: msg.date.toISOString(), note: 'Refund',
    })];
  }
  // Stripe invoice layout (e.g. Anthropic): "Receipt from X S$137.61 Paid September 3, 2026"
  if ((m = /Receipt from (.+?) ([A-Z]{0,2}\$)([\d,]+\.\d{2}) Paid ([A-Za-z]+ \d{1,2}, \d{4})/.exec(text))) {
    var pm2 = /Payment method - (\d{4})/.exec(text);
    var plan = /\d{4} (.+?) Qty \d+/.exec(text);
    return [record(msg, 0, {
      kind: 'purchase', merchant: tidyCompany(m[1]), rawMerchant: m[1], platform: null,
      amount: money(m[3]), currency: currencyFrom(m[2], fallback), card: cardFor(pm2 && pm2[1], cardMap), last4: last4Of(pm2 && pm2[1]),
      date: msg.date.toISOString(), note: plan ? plan[1].replace(/^.*\d{4} /, '') : '',
      subscription: { name: tidyCompany(m[1]), period: 'monthly', renews: null },
    })];
  }
  return [];
}

/** "Iglu Brisbane (Iglu Pty Ltd)" -> "Campus Rooms"; "Anthropic, PBC" -> "Anthropic". */
function tidyCompany(name) {
  return name.replace(/\s*\(.*?\)\s*/g, ' ').replace(/,?\s*(PBC|Pty Ltd|Pte Ltd|Inc\.?|LLC|Ltd\.?)$/i, '').trim();
}

// MARK: - Routing

function record(msg, index, fields) {
  var base = {
    id: msg.id + '-' + index, kind: 'purchase', merchant: '', rawMerchant: '', platform: null,
    amount: '0', currency: 'AUD', card: 'other', date: msg.date.toISOString(), note: '', subscription: null,
  };
  for (var k in fields) base[k] = fields[k];
  return base;
}

/** Which parser handles a sender. Anything else is ignored. */
function parseEmail(msg, cardMap) {
  var from = String(msg.from || '').toLowerCase();
  try {
    if (from.indexOf('sc.com') >= 0) return parseStanChart(msg, cardMap);
    if (from.indexOf('doordash.com') >= 0) return parseDoorDash(msg);
    if (from.indexOf('apple.com') >= 0) return parseApple(msg, cardMap);
    if (from.indexOf('you.co') >= 0) return parseYouTrip(msg);
    if (from.indexOf('stripe.com') >= 0 || from.indexOf('mail.anthropic.com') >= 0) return parseStripe(msg, cardMap);
  } catch (e) {
    // One odd email must never stop the rest from syncing.
    return [];
  }
  return [];
}

/** Gmail search that finds every email the parsers understand. */
var GMAIL_QUERY = [
  'from:alerts.sg@sc.com',
  '(from:no-reply@doordash.com subject:"Order Confirmation")',
  '(from:email.apple.com (subject:"tax invoice" OR subject:"receipt"))',
  '(from:noreply@you.co subject:"Summary of your recent")',
  'from:stripe.com',
  'from:invoice+statements@mail.anthropic.com',
].join(' OR ');

if (typeof module !== 'undefined') {
  module.exports = { parseEmail: parseEmail, normalize: normalize, sgtDate: sgtDate, youTripDate: youTripDate, GMAIL_QUERY: GMAIL_QUERY };
}

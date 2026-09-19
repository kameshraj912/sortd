// Run: node --test apps-script/test
// Samples copy the real email layouts with made-up merchants and card numbers.
const test = require('node:test');
const assert = require('node:assert/strict');
const P = require('../Parsers.js');

const cards = { '1111': 'nab', '2222': 'scDebit', '3333': 'stanchart' };
const one = (msg) => {
  const rows = P.parseEmail(msg, cards);
  assert.equal(rows.length, 1, JSON.stringify(rows));
  return rows[0];
};

test('StanChart purchase alert, time read as Singapore time', () => {
  const r = one({ id: 'a', from: 'alerts.sg@sc.com', subject: 'Transaction Alert Debit Card Email Alert', date: new Date('2026-09-16T04:00:00Z'),
    body: 'Thank you for charging +AUD 24.49 to yr debit card ****2222 on 16-Sep-2611:54 AM at SOME CAFE PTY LTD.\n\nTo modify these alerts' });
  assert.deepEqual([r.kind, r.merchant, r.amount, r.currency, r.card], ['purchase', 'SOME CAFE PTY LTD', '24.49', 'AUD', 'scDebit']);
  assert.equal(r.date, '2026-09-16T03:54:00.000Z');
  assert.equal(r.last4, '2222');
});

test('StanChart descriptors for delivery apps become readable', () => {
  const dd = one({ id: 'b', from: 'alerts.sg@sc.com', subject: 's', date: new Date(), body: 'Thank you for charging +AUD 31.05 to yr debit card ****2222 on 13-Sep-26 12:07 PM at DD *DOORDASH SOMEWHERE. To modify' });
  const ue = one({ id: 'c', from: 'alerts.sg@sc.com', subject: 's', date: new Date(), body: 'Thank you for charging +AUD 33.43 to yr credit card ****3333 on 12-Sep-26 08:53 PM at UBER * EATS PENDING. To modify' });
  assert.deepEqual([dd.merchant, dd.platform], ['DoorDash', 'doordash']);
  assert.deepEqual([ue.merchant, ue.platform, ue.card], ['Uber Eats', 'uber', 'stanchart']);
});

test('StanChart reversal is a refund', () => {
  const r = one({ id: 'd', from: 'alerts.sg@sc.com', subject: 's', date: new Date(), body: 'Transaction of +AUD 17.53 made on your card ****2222 on 11-Sep-26 11:49 AM at DD *DOORDASH SHOP has been reversed. To modify' });
  assert.deepEqual([r.kind, r.amount], ['refund', '17.53']);
});

test('DoorDash confirmation uses Total Charged and the restaurant name', () => {
  const r = one({ id: 'e', from: 'no-reply@doordash.com', subject: 'Order Confirmation for Raj from Test Kitchen', date: new Date(),
    body: 'Paid with Apple Pay\nTest Kitchen\nTotal: $38.15\nSubtotal $35.00\nTotal Charged $38.15' });
  assert.deepEqual([r.merchant, r.amount, r.platform], ['Test Kitchen', '38.15', 'doordash']);
});

test('DoorDash marketing emails are ignored', () => {
  assert.deepEqual(P.parseEmail({ id: 'f', from: 'no-reply@doordash.com', subject: 'Craving something different?', date: new Date(), body: '30% off' }, cards), []);
});

test('Apple invoice gives app, price, card and renewal', () => {
  const r = one({ id: 'g', from: 'no_reply@email.apple.com', subject: 'Your tax invoice from Apple.', date: new Date(),
    body: 'Apple Account:\n\nme@example.com\n\nSomeApp:Tasks\n\nAnnual SomeApp Premium (Annual)\n\nRenews 15 September 2027\n\n$79.99\n\nBilling and Payment\n\nVisa •••• 1111\n\n$79.99' });
  assert.deepEqual([r.merchant, r.amount, r.card, r.subscription.period, r.subscription.renews], ['SomeApp', '79.99', 'nab', 'yearly', '15 September 2027']);
  assert.equal(r.last4, '1111');
});

test('Apple in-app purchase invoice (older layout)', () => {
  const r = one({ id: 'g2', from: 'no_reply@email.apple.com', subject: 'Your tax invoice from Apple.', date: new Date(),
    body: 'Tax Invoice\nAPPLE ACCOUNT\nme@example.com BILLED TO\nVisa .... 1111\nSomeone\nDATE\n23 May 2026\nApp Store\n\nSome App: Match & More\n3 Boosts\nIn-App Purchase\nReport a Problem\n$39.99\n\nTOTAL $39.99\n\nGet help' });
  assert.deepEqual([r.merchant, r.amount, r.card], ['Some App', '39.99', 'nab']);
});

test('YouTrip summary: every row, and a later time means the day before', () => {
  const rows = P.parseEmail({ id: 'h', from: 'noreply@you.co', subject: 'Summary of your recent online purchases & ATM withdrawals', date: new Date('2026-06-02T20:42:49Z'),
    body: '| based on Singapore Time (UTC+8). |\n| | UBER * EATS PENDING~1 Street~Sydney | AUD 32.76 |\n| Ref. No: SFT-1 | 8:24 AM |\n| | SHOP ONE~X | SGD 5.00 |\n| Ref. No: SFT-2 | 2:10 AM |\n| You may view' }, cards);
  assert.equal(rows.length, 2);
  assert.deepEqual([rows[0].merchant, rows[0].amount, rows[0].card], ['Uber Eats', '32.76', 'youtrip']);
  assert.equal(rows[0].date, '2026-06-02T00:24:00.000Z'); // 8:24 AM SGT on 2 June
  assert.equal(rows[1].date, '2026-06-02T18:10:00.000Z'); // 2:10 AM SGT on 3 June
});

test('Stripe receipt, refund and invoice layouts', () => {
  const buy = one({ id: 'i', from: 'receipts+acct_x@stripe.com', subject: 's', date: new Date(), body: 'Receipt from Test Rentals (Test Co Pty Ltd) Receipt #1-2\nAmount paid\nA$68.30\nPayment method\n- 1111' });
  const back = one({ id: 'j', from: 'receipts+acct_x@stripe.com', subject: 's', date: new Date(), body: 'Refund from Meal Co Receipt #3-4\nRefunded\nA$230.05\nRefunded to\n- 3333' });
  const inv = one({ id: 'k', from: 'invoice+statements@mail.anthropic.com', subject: 's', date: new Date(), body: 'Receipt from Some AI, PBC S$137.61 Paid September 3, 2026 Payment method - 9999 Receipt #1 Sep 3–Oct 3, 2026 Pro plan Qty 1 S$137.61' });
  assert.deepEqual([buy.kind, buy.merchant, buy.amount, buy.card], ['purchase', 'Test Rentals', '68.30', 'nab']);
  assert.deepEqual([back.kind, back.amount, back.card], ['refund', '230.05', 'stanchart']);
  assert.deepEqual([inv.merchant, inv.currency, inv.card], ['Some AI', 'SGD', 'other']);
  assert.equal(inv.last4, '9999'); // unknown to CARD_MAP, but the app can still match it
});

test('YouTrip summary as Gmail script text (bold header)', () => {
  const rows = P.parseEmail({ id: 'h2', from: 'noreply@you.co', subject: 'Summary of your recent online purchases & ATM withdrawals', date: new Date('2026-06-02T20:42:49Z'),
    body: 'The times shown are based on *Singapore Time (UTC+8)*.\n\nUBER * EATS PENDING~1 Street~Sydney~2000 036\nAUD 32.76\nRef. No: SFT-1\n8:24 AM\n\nYou may view' }, cards);
  assert.equal(rows.length, 1);
  assert.deepEqual([rows[0].merchant, rows[0].amount], ['Uber Eats', '32.76']);
});

test('YouTrip summary as HTML text (space before the full stop)', () => {
  const rows = P.parseEmail({ id: 'h3', from: 'noreply@you.co', subject: 'Summary of your recent online purchases & ATM withdrawals', date: new Date('2026-06-02T20:42:49Z'),
    body: 'The times shown are based on Singapore Time (UTC+8) . UBER * EATS PENDING~1 Some Street~Sydney AUD 32.76 Ref. No: SFT-1 8:24 AM You may view' }, cards);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].amount, '32.76');
});

test('Stripe invoice refund layout', () => {
  const r = one({ id: 'l', from: 'invoice+statements@mail.anthropic.com', subject: 'Your refund from Some AI', date: new Date(),
    body: 'Refund from Some AI, PBC S$2.48 Refunded on July 3, 2026 (invoice illustration) Receipt number 1 Refunded to - 3333' });
  assert.deepEqual([r.kind, r.merchant, r.amount, r.currency, r.card], ['refund', 'Some AI', '2.48', 'SGD', 'stanchart']);
});

test('Unknown senders produce nothing', () => {
  assert.deepEqual(P.parseEmail({ id: 'z', from: 'ads@bank.example', subject: 'promo', date: new Date(), body: 'S$10 off' }, cards), []);
});

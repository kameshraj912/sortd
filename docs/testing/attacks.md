# Attack list

Written 24 Sep 2026. The list `abuse-tester` works from, one section per bug-hunt area
(the section names match `.claude/workflows/bug-hunt.js`). Each line: input → what
should happen. Tags: `[H]` from the 21 findings in `HANDOVER.md`, `[B]` from
`docs/BugHunt-2026-09-22.md` (fixed there; check it has not come back), no tag = new idea.
A line that fails becomes a test tagged `.knownBug`, then goes to `finding-verifier`.
Add lines when a hunt or a user report finds something new.

## money-parsing

- `MYRTLE CAFE 8.00` → AUD 8.00 (home currency), not ringgit. Markers match whole words. [H]
- `CARMENS 12.00` → not RM; `HOURS. 12.00` → not Indian rupees `RS.`. [H]
- `RM 12.00` and `MYR12.00` → ringgit. Word match must not break the real markers. [H]
- `A$-4.50` and `-A$4.50` and `A$4.50-` and `(A$4.50)` → all a refund of 4.50. [H]
- `12.345` → 12.35 or rejected, never 12,345. [H]
- `4111 1111 1111 1111` (a 16-digit card number) → not an amount. [H]
- `Card ending 4821, A$9.00` → 9.00, not 4821. [H]
- `2 x A$4.50` → 4.50 per item or 9.00 total, never 2. [H]
- `¥1200`, `฿350`, `CHF 12.50`, `₱250`, `CN¥88` → JPY, THB, CHF, PHP, CNY kept, not dropped. [H]
- `¥1200` → shown as ¥1,200, no cents. Same for KRW, VND, IDR. [H]
- `payment for $58.30` → currency is USD or home dollars, never "FOR". [B]
- `rent 1,200` → 1,200; `laptop 1,299` → 1,299, not 9. [B]
- `1.234,56` (EU decimal comma) → 1,234.56; `4,5` → 4.50. [B]
- `Rs. 500` → INR 500. `Rs.500` and `Rs500` too. [B]
- `１２.５０` (full-width digits) → 12.50 or rejected, never a crash. [B]
- `١٢٫٥٠` (Arabic-Indic digits and decimal sign) → 12.50 or rejected, never a crash.
- `12 345,67` with a narrow no-break space (U+202F, fr_FR) → 12,345.67.
- `1'234.50` (de_CH apostrophe) → 1,234.50.
- `A$ 0.00` → not logged as a purchase.
- `A$999999999999.99` → rejected as absurd, no overflow, no crash.
- `A$4.50 A$5.00` (two amounts) → the total line wins, or ask; never the first by accident.
- `S$25` in an SGD-home profile → no FX step; in AUD home → one FX step, not two.
- `$25` with no country marker → the home currency, and flagged as a guess.
- Emoji in the amount string `💸A$4.50` → 4.50.
- A 10,000-character string with no digits → nil, returns in under 50 ms.
- `NaN`, `inf`, `1e5` → rejected, not parsed by `Double()`.

## gmail-security

- A bank alert with "otp" inside a word (`HOTPOT DINING`) → still a purchase. [B]
- A receipt whose footer says "privacy policy" → still a purchase. [B]
- A real OTP email ("Your one-time code is 482193") → not a purchase, and the code is never stored.
- Empty body, subject only → skipped quietly, sync goes on.
- HTML-only email (no text/plain part) → parsed from the HTML text, tags stripped.
- Quoted-printable body with `=3D` and soft line breaks inside the amount (`A$4=\n.50`) → 4.50.
- base64 body with a UTF-8 BOM → parsed like plain text.
- A forwarded receipt ("Fwd:", quoted with `>`) → one purchase, the original shop, not the forwarder.
- The same receipt in two threads → one purchase.
- More than 1,000 matches in 120 days → sync finishes over several runs. [B]
- Delete All Data during a sync → nothing comes back. [B]
- Pro lapses mid-sync → sync stops; no new Gmail rows after lapse. [B]
- Refresh token revoked on Google's side → one clear "reconnect Gmail" message, no retry loop.
- Two syncs at once (pull-to-refresh while background sync runs) → one runs, the other waits or skips; no double rows.
- A sender spoofing the bank's display name from another domain → not trusted.
- Network drops halfway → the next sync picks up, no gap and no duplicates.
- App Lock on with no iPhone passcode → the app opens and App Lock turns off. [B]
- Keychain item missing after restore to a new phone → Gmail shows disconnected, no crash.
- Crash report or log line → never contains an email body, merchant or amount.

## data-backup

- A Gmail receipt that merges into a purchase pending delete → the purchase is kept or cleanly re-added, not lost. [H]
- A backup with the same id twice → restored once; total not doubled. [H]
- Restore the same backup twice → no new rows the second time. [H]
- A backup row with a negative amount → treated as a refund or rejected; no month below zero. [H]
- Backup from an SGD-home phone restored on an AUD-home phone → totals converted once, right. [B]
- "Replace Everything" → monthly budget converted once, not twice. [B]
- Restore then reconnect Gmail → deleted purchases stay deleted. [B]
- A backup with sample data in it → sample data can still be cleared. [B]
- A truncated backup file (cut halfway) → clear error, nothing half-imported.
- A backup from a newer app version with an unknown field → field ignored or clear error, no crash.
- A backup with an unknown category or card raw string → falls back to Other, row kept.
- Two payments of A$4.50 at one shop a minute apart, different cards → two rows. [H]
- Two identical taps two seconds apart from one card → one row (true duplicate).
- A recharge after a refund at the same shop → counted. [H]
- A refund tap more than 10 minutes after the purchase → lowers the total, or does not say "Refund noted". [B]
- Delete a purchase while a sync is inserting its twin → one outcome, no crash.
- Schema change with an old store on disk → migrates, no launch crash. [B]
- Device storage full during save → error shown, no half-written store.
- A purchase on 29 Feb 2028 → shows in February, monthly totals right.
- A tap at 02:30 on the DST change day (Sydney, first Sunday of October) → one row, right day.
- A tap at 23:59 in Singapore, phone later set to Sydney → stays on the day it happened.
- Export to CSV with a merchant containing a comma, quote or newline → the CSV still opens right.

## ui-intents-widget

- Widget after a tap, add, edit or delete → refreshed. "Today" after midnight → today. [B]
- Wallet tap text `A$1234.50` with no commas → 1,234.50, not 123. [B]
- Shortcut text with newlines between fields → parsed the same as one line.
- Shortcut text with the merchant missing → logged as "Unknown" with the amount, not dropped.
- Shortcut text with the amount missing → nothing logged, and the Last Tap line says why.
- Shortcut text that is empty or only spaces → nothing logged, no crash.
- Shortcut text in another language (e.g. Japanese date and ¥ amount) → amount and currency right.
- `LogPurchaseIntent` with nil amount, nil merchant or nil card → clear Siri error, no crash.
- `LogPurchaseIntent` amount 0 or negative → refused, or logged as a refund when negative.
- Two taps delivered at the same moment → two rows, no lost write.
- Siri "Upcoming Bills" as a free user → Pro prompt, not the data. [B]
- Bills widget tap → opens Subscriptions & Bills. [B]
- Merchant with RTL text (`مطعم`), mixed with a Latin amount → row and VoiceOver read in the right order.
- Merchant with emoji and ZWJ (`👩‍🍳 Kitchen`) → no broken glyphs, no clipping.
- Merchant 200 characters long → truncated with an ellipsis; amount never cut.
- Amount `A$123,456.78` on iPhone SE at AX5 Dynamic Type → fully visible or wraps; never "A$12…".
- VoiceOver on any amount → spoken with `Money.spoken()` ("25 Singapore dollars").
- Dark mode and Increase Contrast → text still passes 4.5:1.
- Reduce Motion on → no zoom transition, cross-fade instead.
- Free and lapsed users → no Pro reminders. [B]

## statement-import

- Full-width (`１２`) or Arabic (`١٢`) digits in a date → skipped or parsed, never a crash. [B]
- `12.50 1,034.20` (amount then running balance) → 12.50. [B]
- `CAFE 12 MARKET` → the date is not 12 March. [B]
- A year-less `28 Dec` imported in January → last December, not this one. [B]
- Two identical rows in one statement → two purchases. [B] [H]
- Import the same statement twice → no new rows the second time. [H]
- A row with no date → kept with a flag, or listed as skipped. Never silently dropped. [H]
- `31/02/2026`, `01/01/1900`, `01/01/2099` → rejected as absurd. [H]
- `03/04/2026` in an AU statement → 3 April, not 4 March. US-format banks are detected, not guessed per row.
- A CSV with a BOM, CRLF endings, or `;` as the separator → parsed.
- A CSV where the merchant cell has a quoted comma (`"SMITH, JOHN & CO"`) → one column.
- Debits and credits in separate columns → credits are refunds, not purchases.
- A PDF with the table split across pages → no row lost or doubled at the page break.
- A 10,000-row statement → imports with a spinner, UI stays responsive, finishes.
- A file that is not a statement (a photo renamed .csv) → clear error.
- Amounts in brackets `(45.00)` → a credit.
- A merchant with Unicode (`Café Déjà Vu`, `東京ラーメン`) → kept as is, categorised, de-duplicated.
- Statement currency differs from home currency → converted once at the row's date.

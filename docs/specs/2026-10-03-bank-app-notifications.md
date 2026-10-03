# Online payments from the bank app's notification

3 Oct 2026. Follows `2026-09-26-apple-pay-failsafes.md`. Research: `docs/research/2026-10-03-online-apple-pay.md`.

## Problem

Apple Pay inside apps and on websites does not fire the Wallet tap trigger. PR #105 added a
second trigger, "When I receive a notification from Wallet". Two things are still unknown:
whether Shortcuts passes Wallet's notifications on at all (it did not on the simulator), and
whether each bank makes Wallet show one. Other trackers that cover online payments (finerd)
point the iOS 27 Notification trigger at **the bank's own app**. That also covers card
payments that are not Apple Pay.

## What changes

1. **Reading.** A notification run can now be a bank app's sentence, not only Wallet's short
   lines. New pure reader `BankNotice` (in `Spend/Services/`), used by
   `WalletNotification.read` when the text reads as a sentence:
   - Logs only when the text says money was spent: a spend word (spent, purchase, paid,
     payment of, charged, transaction of, debited, used at…) **and** an amount.
   - Shop: what follows "at", "to", "@" or "with merchant", up to "on", "with", "using",
     "card", "ending", a date, or the end. Trim trailing full stops and "Pty Ltd".
   - Card: masked digits ("ending 4821", "•••• 4821", "x4821") go through the existing
     card matching. No card words means the card is left to the usual default.
   - Currency: "SGD 23.40", "S$23.40", "A$23.40", "AUD23.40", "$23.40" (bare `$` = home).
   - Never a purchase: one-time codes (OTP, "verification code", "do not share"), money
     coming in (received, deposit, credited, salary, transfer from), balance or limit
     alerts with no spend word, declined/failed (existing rule), marketing ("cashback",
     "offer", "win", "% off") with no spend word, refunds go to the existing refund path.
   - Anything else with an amount but no spend word is **not logged** and makes no
     "needs a check" row. A bank app sends many notifications; a wrong purchase is worse
     than a missed one.
2. **One purchase, up to three signals.** A tap, Wallet's notification and the bank's
   notification for the same payment merge into one row (same amount and currency inside
   the existing window; shop names may differ, e.g. "DOORDASH*ORDER" vs "DoorDash").
   `Transaction.tapOrigins` gains "b" for a bank-app run. The first shop name with real
   letters wins; a later bank name never overwrites a tap's.
3. **Setup words (iOS 27 only).** Step 3 stays "Turn both automations on". One new quiet
   line under the steps: "For payments in apps and on websites, tap + next to Wallet in the
   shortcut and add your bank's app. Turn on purchase alerts in that app." The scope line
   becomes: "Taps in shops log from the tap. Payments in apps and on websites log from a
   notification, from Wallet or from your bank's app."
4. **What is kept.** Bank apps also send codes and balances. `recordReach` keeps the raw
   text of a notification run only when it was read as a payment. For every other
   notification run it keeps "notification run · not a purchase" and no text. (DEBUG builds
   keep the raw text, for tuning on Raj's phone.) Nothing from a notification goes to
   analytics or Sentry.
5. **Privacy text** (in-app Privacy page; the site follows through issue #79): "If you add
   your bank's app to the shortcut, iOS passes that app's notifications to Sortd on your
   iPhone. Sortd keeps the ones that are purchases and ignores the rest. Nothing is sent
   anywhere."

## Not in this change

- Per-bank shortcut files with the bank app pre-filled (needs each bank's bundle id and a
  phone to check each one).
- Bank SMS through the Message trigger.
- FinanceKit: US and UK only.

## Sample texts (made up to look like bank notices; real ones are not published)

The real wording comes from Raj's phone test; the developer menu's Recent Runs shows it.

| Text | Result |
|---|---|
| "You spent $23.40 at DOORDASH with your card ending 4821." | A$23.40, DoorDash, card 4821 |
| "A transaction of SGD 31.80 was made with your DBS card ending 1234 at UBER EATS on 03 Oct." | S$31.80, Uber Eats, card 1234 |
| "Purchase of AUD 5.50 at Seven Seeds Carlton" | A$5.50, Seven Seeds Carlton |
| "Card purchase: $12.00 to NETFLIX.COM" | A$12.00, Netflix.com |
| "Your OTP is 482193. Do not share it. Amount SGD 31.80 at UBER" | nothing |
| "You received $50.00 from J TAN via PayID" | nothing |
| "Your available balance is $1,204.11" | nothing |
| "Payment of $23.40 to DOORDASH was declined" | nothing (existing rule) |
| "Refund of $23.40 from DOORDASH" | refund path |
| "Get $20 cashback when you spend $100 at Myer" | nothing |
| "Your credit card payment of $500.00 is due on 12 Oct" | nothing (bill reminder, not a purchase) |

## Open, for the phone test

- Does Wallet's own notification reach the trigger on a real iPhone?
- What does Raj's bank app actually send? Tune `BankNotice` from Recent Runs.
- Does adding a second app with "+" keep both, and does each fire?

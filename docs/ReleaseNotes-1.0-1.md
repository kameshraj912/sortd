# Sortd 1.0 (1) — first TestFlight build

Planned upload: Mon 5 Oct 2026. First build ever sent to App Store Connect.

## In this build
- Apple Pay logging with one ready-made shortcut: taps in shops (iOS 26 and 27) and payments in
  apps and on websites from Wallet's notification (iOS 27). Runs are silent; Sortd posts its own
  "Logged" notice.
- Activity is one scrolling list again: search across every day, Go to Date, clearer day totals.
- Receipt camera, statement import (CSV, PDF, screenshot), budgets and category limits,
  subscriptions and bills with reminders, Insights, multi-currency.
- Widgets: Spending, Budget Ring, Today, Recent, plus Lock Screen.
- App Lock with Face ID or passcode; iCloud backup; sign in with Apple or Google (optional).
- Drafts survive closing the app; saves that fail say so; backup and exchange rates catch up
  when the phone is back online.

## Not in this build
- Session replay is off (no screen recording in this build).
- No tip jar (the row hides until the tips exist in App Store Connect).
- Online Apple Pay on iOS 26, and logging from a bank's own app or bank texts: planned for a
  later beta (`docs/specs/2026-10-03-bank-app-notifications.md`).
- The account Worker is not deployed, so Delete Account queues the server step.

## What to Test text
See `docs/TestFlightWhatToTest.md` (beta description and What to Test for this build).

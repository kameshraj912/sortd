# TestFlight — beta description and What to Test

Paste into App Store Connect › TestFlight. The beta description goes in Test Information ›
Beta App Description (once per app). "What to Test" goes on each build. Both are under 200
words. Written 26 Sep 2026 for the first build (1.0, build 1).

## Beta App Description

Sortd writes down what you spend. Pay with Apple Pay and the shop, the amount and the card
land in the app a few seconds later. No bank login, no typing.

Everything stays on your iPhone. There is no Sortd server. Sign-in and iCloud backup are
optional; every screen works without them.

What it does today:
- Logs Apple Pay taps through one Shortcuts automation. Setup shows a picture for each step.
- Scans paper receipts with the camera.
- Imports a CSV or PDF statement, or a screenshot of your bank app.
- Shows the month by category and by card, in your home currency.
- Finds subscriptions and bills, flags price rises, reminds you the day before.
- Home Screen and Lock Screen widgets.

Sortd is free. Every feature. The tip jar in Settings › About is the only thing for sale and
it unlocks nothing.

It is a beta, so things will break. When one does, shake the phone or use TestFlight's
feedback button and tell us what you tapped. Screenshots help.

Support: support@sortd.page.

## What to Test (build 1.0 (1))

Thanks for trying Sortd. Three things matter most this round.

1. Apple Pay logging. Settings › Purchase Sources › Apple Pay Logging, follow the pictures,
   then buy something small with Apple Pay at a staffed till. Did it appear in Activity within
   a minute, with the right shop, amount and card? If not, send the Last Tap Received text from
   that Settings page.

2. Receipts and statements. Scan two or three paper receipts, then import a CSV or PDF
   statement. Check the amount, the shop and the date. Wrong total, a missed line, or a refund
   counted as spending: tell us which shop or bank.

3. Sign-in and iCloud backup. Sign in with Apple or Google, turn on Back up to iCloud, then
   restore on the same phone. Anything missing after Restore is a bug. Sign Out and Delete
   Account should both work without touching your purchases unless you choose to.

Also worth a look: the setup flow on a fresh install, Dark Mode and the largest text size in
Settings › Accessibility.

Sessions are recorded during the beta (Settings › Privacy has the switch), with text fields
like the amount, shop and note masked before anything leaves your phone.

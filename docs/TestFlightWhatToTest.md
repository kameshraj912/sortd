# TestFlight — beta description and What to Test

Paste into App Store Connect › TestFlight. The beta description goes in Test Information ›
Beta App Description (once per app). "What to Test" goes on each build. Both are under 200
words. Written 26 Sep 2026 for the first build (1.0, build 1).

## Beta App Description

Sortd writes down what you spend. Pay with Apple Pay and the shop, the amount and the card
land in the app a few seconds later. No bank login, no typing.

Your purchases stay on your iPhone. Sign-in and iCloud backup are optional; every screen
works without them.

What it does today:
- Logs Apple Pay through one ready-made Shortcuts automation: taps in shops on iOS 26 and 27,
  and payments in apps and on websites on iOS 27 (from Wallet's notification). Setup shows a
  picture for each step.
- Scans paper receipts with the camera.
- Imports a CSV or PDF statement, or a screenshot of your bank app.
- Shows the month by category and by card, in your home currency.
- Finds subscriptions and bills and reminds you the day before.
- Home Screen and Lock Screen widgets, and App Lock with Face ID.

Sortd is free. Every feature.

It is a beta, so things will break. When one does, take a screenshot and send it with
TestFlight's feedback button, and say what you tapped.

Support: support@sortd.page.

## What to Test (build 1.0 (1))

Thanks for trying Sortd. Three things matter most this round.

1. Apple Pay logging. Settings › Purchase Sources › Apple Pay Logging, tap Get the Shortcut
   and follow the pictures. Then pay for something small with Apple Pay in a shop. On iOS 27,
   also pay for something in an app or on a website with Apple Pay. Did each appear in
   Activity within a minute, with the right shop, amount and card? If not, tell us your bank
   and what Wallet's notification said. A guide with a picture of every step:
   sortd.page/setup-guide.pdf

2. Receipts and statements. Scan two or three paper receipts, then import a CSV or PDF
   statement or a screenshot of your bank app. Check the amount, the shop and the date.

3. iCloud backup. Turn on Back up to iCloud, then restore. Anything missing is a bug.

Also worth a look: setup on a fresh install, Activity (scroll, search, Go to Date in the
filter menu), App Lock, Dark Mode and the largest text size.

## What to Test (build 1.0 (7), 5 Oct 2026)

Two fixes in this build.

1. Pressing ▶ in the shortcut now tells you it worked. Until your first real purchase, a test
   run shows a "Shortcut connected" notification (if notifications are on). Nothing is saved.

2. Travelling. A tap that arrives without a currency now uses the currency of the country
   you are in, wherever your iPhone was bought. If you are away from home, pay for something
   with Apple Pay and check the currency in Activity.

Everything else is as before: Apple Pay logging, receipts, statements, iCloud backup.

## What to Test (build 1.0 (8), 6 Oct 2026)

This build is for iPhones on iOS 26. Setup there was too hard, and people got stuck.

1. Setup no longer locks you out. After you add the shortcut and run it once (steps 1 and 2),
   you can go into the app. Home shows "Apple Pay isn't logging yet" with a button back to
   step 3 until it is done.

2. Step 2 now says what you see: in Shortcuts, tap Log Apple Pay in Sortd to run it.

3. Step 3, in Shortcuts: if you type Wallet and the list goes empty, delete the space after
   the word. The guide now says so.

4. Coming back from Shortcuts lands on the steps, not on the file page.

If you are on iOS 26 and step 3 still beats you, record your screen and send it with
TestFlight's feedback button. That is the most useful thing you can send us.


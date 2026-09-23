# App Review notes — draft

Paste the "Notes" part into App Store Connect › App Review Information › Notes. Keep it under
4,000 characters. Fill in the placeholders first.

---

## Notes

Sortd is a personal spending tracker. It doesn't move, hold or manage money, doesn't connect to
any bank and never asks for bank logins. No login, no Sortd account, no server: all data is
stored on the device.

**Quickest way to review**
On the first screen tap "Look around with sample data": about two months of purchases on two
sample cards. Home, Activity, Settings and card pages are free. Tap "Clear" on the Home banner to
go back to setup.

**Sortd Pro (in-app purchases)**
Gmail receipts, Insights, Subscriptions & Bills (with local bill reminders), the receipt camera
and category budgets are Pro; tapping one shows the paywall. Three products, same features:
Yearly (auto-renewable, 2-week free trial for new subscribers), Monthly (auto-renewable),
Lifetime (one-time). A sandbox purchase unlocks Pro and fills Insights and Subscriptions & Bills.
The paywall shows the trial, the price after it and how to cancel, plus Restore Purchases, Terms
and Privacy. Terms and Privacy are also in Settings › Privacy & Security › Privacy.
Ongoing value: new receipt formats and bank layouts, more currencies, regular updates.

**Logging Apple Pay taps (Shortcuts automation)**
Sortd can't read Wallet itself. The user makes a personal automation. iOS 27: Shortcuts › + ›
Edit › Automation › Wallet › add Sortd's "Log Wallet Tap" (App Intent) and set its field to the
Transaction. (iOS 26: Automation tab › Wallet › Run Immediately.) Each in-store Apple Pay tap is
then logged, even with the app closed. Guide with pictures: Settings › Purchase Sources › Apple
Pay Logging. ▶ in Shortcuts is a test: Sortd says "connected" and saves nothing. Needs a real
device with a Wallet card; video: [VIDEO LINK]. Purchases can always be added by hand.

**Gmail (optional, Pro)**
Settings › Purchase Sources › Connect Gmail. The app explains what it reads first, then opens
Google OAuth in ASWebAuthenticationSession with `gmail.readonly`. Only receipts and bank alerts
are searched and read on the device; the only requests go to Google. Refresh token in the
Keychain. Disconnect revokes access and can delete that account's purchases. Google sign-in only
reaches the user's own mail, not an app login, so Sign in with Apple doesn't apply.
Test account: [TEST GMAIL ADDRESS] / [TEST GMAIL PASSWORD]

**New: setup questions, check-in, typing a purchase**
- Setup asks optional questions (goals, how they pay, feeling about spending, check-in time,
  spending abroad). Stored only on the device; used for setup steps, Pro feature order and the
  check-in time. Change: Settings › Help & Feedback › Run Setup Again. Delete All Data removes them.
- Check-in (free): a repeating local notification (8 am, 8 pm or Sunday 6 pm), fixed text, no
  amounts, no marketing. iOS's permission alert appears only after the user picks a time; "Not
  now" and "Only when it matters" skip it. Settings › Bills & Reminders › Check-in. All
  notifications are local (UNUserNotificationCenter); no push server, and none are required.
- Add › the top line ("coffee 5.50 yesterday") is read by Apple's on-device model where Apple
  Intelligence is on, otherwise by plain rules. Nothing leaves the device; it only fills the form.
- Home › "Finish setup" checks for a Sortd widget with WidgetKit, on the device.

**Other**
- Exchange rates: frankfurter.dev (ECB data). Only currency codes and a date are sent.
- Scan Receipt: camera or one photo, read on the device (Vision, plus the on-device model where
  available). Photo not stored or sent; the user checks the result before saving.
- Cards: only the last 4 digits of the card and of its Apple Pay number.
- Settings › Backup & Data: Save a Backup, Import, Export as Spreadsheet, Delete All Data. Files
  are only made when the user taps, via the share sheet.
- No tracking, ads or analytics. Privacy policy: https://sortd.page/privacy

Contact: [REVIEW CONTACT NAME], [REVIEW CONTACT PHONE, +61 format], [CONTACT EMAIL]

---

## Before submitting

- [ ] Notes are ~3,940 characters with placeholders. After filling them in, check it's still
      under 4,000; cut the "Other" list first if not.
- [ ] Record the Shortcuts setup video on a real iPhone and attach it (or link it above).
- [ ] Type the real test password only into App Store Connect. Never commit it to this file.
- [ ] Create the test Gmail account, send it a few real-looking receipts, and add it as a Google
      OAuth test user. Don't use a personal account.
- [ ] Submit only after Google has verified gmail.readonly. Before that, reviewers can't connect
      Gmail (only listed test users can).
- [ ] Check that Settings › Apple Pay Auto-Logging still says online Apple Pay "will come from
      your email receipts in the next update" — Gmail is now in the app, so that line is out of
      date (Swift change, not part of this doc).

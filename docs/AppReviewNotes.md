# App Review notes — draft

Paste the "Notes" part into App Store Connect › App Review Information › Notes. Keep it under
4,000 characters. Placeholders in [square brackets] are the ones only Raj can fill; see the list
at the bottom. Updated 26 Sep 2026: sign-in and iCloud backup are on, contact name and email
filled from the repo.

---

## Notes

Sortd is a personal spending tracker. It doesn't move, hold or manage money, doesn't connect to
any bank and never asks for bank logins. Purchases are stored on the device only. Sign-in is
optional and nothing needs it.

**Quickest way to review**
On the first screen tap "Look around with sample data": about two months of purchases on two
sample cards, across every screen. Tap "Clear" on the Home banner to go back to setup.

**Every feature is free**
Gmail receipts, Insights, Subscriptions & Bills (with local bill reminders), the receipt camera
and category budgets: nothing is locked. Settings › About › Leave a tip offers three consumable
tips that unlock nothing. Terms and Privacy are in Settings › Privacy & Security › Privacy.

**Logging Apple Pay taps (Shortcuts automation)**
Sortd can't read Wallet itself; the user makes a personal automation. iOS 27: Shortcuts › + ›
Edit › Automation › Wallet › add Sortd's "Log Wallet Tap" (App Intent) and set its field to the
Transaction. (iOS 26: Automation tab › Wallet › Run Immediately.) Each in-store Apple Pay tap is
then logged, even with the app closed. Guide with pictures: Settings › Purchase Sources › Apple
Pay Logging. ▶ in Shortcuts is a test: Sortd says "connected" and saves nothing. Needs a real
device with a Wallet card; video: [VIDEO LINK]. Purchases can always be added by hand.

**Sign-in (optional, Apple or Google)**
Settings › Account. Only the provider's subject and, if shared, the email are kept, in the
Keychain on the device; no Sortd server holds user data. Sign Out forgets the identity. Delete
Account asks the provider to cancel the sign-in and removes the usage record (5.1.1(v)), with
an option to also delete all data on the device.

**Gmail (optional)**
Settings › Purchase Sources › Connect Gmail. The app explains what it reads first, then opens
Google OAuth in ASWebAuthenticationSession with `gmail.readonly`. Only receipts and bank alerts
are read, on the device; the only requests go to Google. Refresh token in the Keychain. Disconnect revokes access and can delete that account's purchases.
Test account: [TEST GMAIL ADDRESS] / [TEST GMAIL PASSWORD]

**Setup questions, check-in, typing a purchase**
- Setup asks optional questions (goals, how they pay, check-in time, spending abroad). Stored
  only on the device. Change: Settings › Help & Feedback › Run Setup Again. Delete All Data
  removes them.
- Check-in: a repeating local notification (8 am, 8 pm or Sunday 6 pm), fixed text, no amounts,
  no marketing. iOS's permission alert appears only after the user picks a time; "Not now" and
  "Only when it matters" skip it. Settings › Bills & Reminders › Check-in. All notifications are
  local (UNUserNotificationCenter); no push server, and none are required.
- Add › the top line ("coffee 5.50 yesterday") is read by Apple's on-device model where Apple
  Intelligence is on, otherwise by plain rules. Nothing leaves the device; it only fills the form.
- Home › "Finish setup" checks for a Sortd widget with WidgetKit, on the device.

**Other**
- Exchange rates: frankfurter.dev (ECB data); only currency codes and a date are sent.
- Scan Receipt: camera or one photo, read on the device (Vision, plus the on-device model where
  available). Photo not stored or sent; the user checks the result before saving.
- Cards: only the last 4 digits of the card and its Apple Pay number.
- Settings › Backup & Data: Back up to iCloud (encrypted on the device, the user's own iCloud
  private database), Save a Backup, Import, Export as Spreadsheet, Delete All Data. Files are
  only made when the user taps, via the share sheet.
- No tracking or ads. Usage analytics (PostHog) and crash reports (Sentry) are on, linked to a
  salted hash, scrubbed of purchases, merchants, emails and IP, and share one switch in
  Settings › Privacy. Privacy policy: https://sortd.page/privacy

Contact: Kameshraj Gnanaprakasam, [REVIEW CONTACT PHONE, +61 format], support@sortd.page

---

## Filled from the repo (26 Sep 2026)

- Contact name: Kameshraj Gnanaprakasam (the copyright holder in `docs/AppStoreListing.md`).
- Contact email: support@sortd.page (the support address on sortd.page and in the app).

## Only Raj can fill

- `[REVIEW CONTACT PHONE, +61 format]`: a phone number App Review can call, in international
  format. Type it straight into App Store Connect; it does not need to be in this file.
- `[VIDEO LINK]`: the Shortcuts setup video, recorded on a real iPhone (see below).
- `[TEST GMAIL ADDRESS]` and `[TEST GMAIL PASSWORD]`: a throwaway Google account added as an
  OAuth test user. The password goes only into App Store Connect, never into this file.
- Whether to give App Review a demo sign-in account. Sign-in is optional and every screen works
  without it, so the notes say so instead of supplying one.

## Before submitting

- [ ] Notes are about 4016 characters with the placeholders in. Once the real values are in,
      check it is under 4,000; cut the "Other" list first if not.
- [ ] Record the Shortcuts setup video on a real iPhone and attach it (or link it above).
- [ ] Type the real test password only into App Store Connect. Never commit it to this file.
- [ ] Create the test Gmail account, send it a few real-looking receipts, and add it as a Google
      OAuth test user. Don't use a personal account.
- [ ] Submit only after Google has verified gmail.readonly. Before that, reviewers can't connect
      Gmail (only listed test users can).
- [x] The Apple Pay Logging page no longer says online Apple Pay "will come from your email
      receipts in the next update". Checked 26 Sep 2026: `SetupGuideView.swift` says "In-app and
      online Apple Pay comes from your email receipts."

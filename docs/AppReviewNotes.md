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

Contact: Kameshraj Gnanaprakasam, support@sortd.page (phone given in App Store Connect only)

---

## Filled from the repo (26 Sep 2026)

- Contact name: Kameshraj Gnanaprakasam (the copyright holder in `docs/AppStoreListing.md`).
- Contact email: support@sortd.page (the support address on sortd.page and in the app).
- Contact phone: entered in App Store Connect only. Not kept in the repo, which is public.

## Two things that need a phone in hand

Sign-in needs no demo account: it is optional and every screen works without it, and the
notes say so.

### 1. The Shortcuts video (`[VIDEO LINK]`)

Screen-record on the iPhone, under 90 seconds, no voice needed. Control Centre › Screen
Recording. Then AirDrop it to the Mac and upload it as an unlisted YouTube video or an iCloud
Drive share link, and paste the link into the notes. Shots, in order:

1. Sortd › Settings › Purchase Sources › Apple Pay Logging. Scroll the picture guide once.
2. Tap Get the Shortcut. Shortcuts opens. Show the automation: Wallet › Sortd "Log Wallet Tap"
   with the Transaction in its field. Tap ▶ once: Sortd shows "connected".
3. Stop recording. Buy something small with Apple Pay at a staffed till (a coffee is fine).
4. Start recording again within a minute: open Sortd › Activity. The purchase is on top with
   the shop, amount and card. Tap it to show the detail. Stop.

Trim the two clips together in Photos or iMovie. If the till clip is awkward, skip it and
just show the purchase landing; the reviewer only needs to see the automation and the result.

### 2. The test Gmail account (`[TEST GMAIL ADDRESS]` / `[TEST GMAIL PASSWORD]`)

1. In a private browser window, accounts.google.com › Create account › For personal use. Name
   "Sortd Review", any free address such as sortd.review.<year>@gmail.com. Google will ask for a
   phone for verification; the +61 number above works and is not shown to reviewers.
2. Google Cloud › APIs & Services › OAuth consent screen (Google Auth Platform › Audience) ›
   Test users › Add: that address. Needed until Google finishes the gmail.readonly review.
3. From any account, send the three emails below to the new address. They match the parsers
   (`Spend/Services/EmailParsers.swift`, `BankAlerts.swift`): a delivery, a ride and a bank
   alert. Change nothing but the dates.
4. Sign in to Sortd's Connect Gmail with it once yourself to confirm the three land in
   Activity. Disconnect afterwards.
5. Type the address and password into App Store Connect › App Review Information › Sign-in
   required. Never into this file.

Email A. From any address, subject `Your Uber Eats order receipt`:

    Thanks for ordering with Uber Eats.
    Total  AUD 24.90
    Order from Grill'd Melbourne Central
    Paid with Visa ••••4321
    Date: <today>

Email B. Subject `Your Tuesday morning trip with Uber`:

    Total  AUD 18.60
    Trip with Uber
    Payment: Mastercard ••••9876
    <today>

Email C. Subject `NAB: transaction alert`:

    A purchase of $6.50 was made at WOOLWORTHS 1234 MELBOURNE on <today> using your NAB Visa
    card ending in 4321.

If any of the three does not appear after a sync, it is a parser gap, not a reason to change
the email: log it as a finding.

## Before submitting

- [ ] Notes are about 3997 characters with the placeholders in. Once the real values are in,
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

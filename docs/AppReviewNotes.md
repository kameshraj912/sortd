# App Review notes — draft

Paste the "Notes" part into App Store Connect › App Review Information › Notes. Keep it under
4,000 characters. Placeholders in [square brackets] are the ones only Raj can fill; see the list
at the bottom. Updated 26 Sep 2026: sign-in and iCloud backup are on, contact name and email
filled from the repo. Updated 2 Oct 2026: Gmail removed (no Gmail steps or test account any more);
Budget Ring, Today and Recent widgets added.

---

## Notes

Sortd is a personal spending tracker. It doesn't move, hold or manage money, doesn't connect to
any bank and never asks for bank logins. Purchases are stored on the device only. Sign-in is
optional and nothing needs it.

**Quickest way to review**
On the first screen tap "Look around with sample data": about two months of purchases on two
sample cards, across every screen. Tap "Clear" on the Home banner to go back to setup.

**Every feature is free**
Insights, Subscriptions & Bills (with local bill reminders), the receipt camera
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

**Setup questions, check-in, typing a purchase**
- Setup asks optional questions (goals, how they pay, check-in time, spending abroad), stored
  only on the device. Change: Settings › Help & Feedback › Run Setup Again. Delete All Data
  removes them.
- Check-in: a repeating local notification (8 am, 8 pm or Sunday 6 pm), fixed text, no amounts,
  no marketing. iOS's permission alert appears only after the user picks a time. Settings ›
  Bills & Reminders › Check-in. All notifications are local; no push server.
- Add › the top line ("coffee 5.50 yesterday") is read by Apple's on-device model where Apple
  Intelligence is on, otherwise by plain rules. Nothing leaves the device.
- Home › "Finish setup" checks for a Sortd widget with WidgetKit, on the device.
- Widgets: Budget Ring, Today and Recent show the budget left, today's total and the last three
  purchases, read on the device. Shop names and amounts are hidden while
  the iPhone is locked.

**Other**
- Exchange rates: frankfurter.dev (ECB data); only currency codes and a date are sent.
- Scan Receipt: camera or one photo, read on the device. Not stored or sent; the user checks
  the result before saving.
- Cards: only the last 4 digits of the card and its Apple Pay number.
- Settings › Backup & Data: Back up to iCloud (encrypted on the device, the user's own iCloud
  private database), Save a Backup, Import, Export as Spreadsheet, Delete All Data. Files are
  only made when the user taps.
- No tracking or ads. Usage analytics (PostHog) and crash reports (Sentry) are linked to a
  salted hash, scrubbed of purchases, merchants, emails and IP, and share one switch in
  Settings › Privacy. The switch starts off when the iPhone's region is in the EU/EEA, the UK
  or Switzerland, and on elsewhere. Privacy policy: https://sortd.page/privacy

Contact: Kameshraj Gnanaprakasam, support@sortd.page (phone given in App Store Connect only)

---

## Filled from the repo (26 Sep 2026)

- Contact name: Kameshraj Gnanaprakasam (the copyright holder in `docs/AppStoreListing.md`).
- Contact email: support@sortd.page (the support address on sortd.page and in the app).
- Contact phone: entered in App Store Connect only. Not kept in the repo, which is public.

## One thing that needs a phone in hand

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

## Before submitting

- [ ] Notes are about 3,600 characters with the placeholders in (measured 2 Oct 2026). Once the
      real values are in, check it is under 4,000; cut the "Other" list first if not.
- [ ] Record the Shortcuts setup video on a real iPhone and attach it (or link it above).
- [x] The Apple Pay Logging page does not promise online Apple Pay from email receipts. Checked
      2 Oct 2026: `SetupGuideView.swift` says "Add in-app and online Apple Pay by hand."

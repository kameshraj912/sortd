# App Review notes — draft

Paste the "Notes" part into App Store Connect › App Review Information › Notes. Keep it under
4,000 characters. Fill in the placeholders first.

---

## Notes

Sortd is a personal spending tracker. There is no login and no Sortd account. All data is stored
on the device. The app doesn't move money and doesn't connect to any bank.

**Quickest way to review**
On the first screen, tap "Explore with sample data". This loads about two months of sample
purchases on two sample cards, so every screen has content: Home, Activity, Insights,
Subscriptions & Bills, and Settings. A banner on Home says it's sample data; tap "Clear" to
remove it and go back to setup.

**Logging Apple Pay taps (needs a Shortcuts automation)**
Sortd can't read Apple Wallet by itself. The user creates a personal automation in the
Shortcuts app. On iOS 27: Shortcuts › + › Edit › Automation › Wallet ("When I tap a Wallet
Card or Pass") › add Sortd's "Log Wallet Tap" action (an App Intent) and set its one field to
the Transaction. (On iOS 26: Automation tab › Wallet › Run Immediately.) After that, each
in-store Apple Pay tap is logged, even with the app closed. Setup shows each step with a picture;
it's also at Settings › Apple Pay Auto-Logging. Pressing ▶ in Shortcuts is a test run: Sortd
replies "connected" and saves nothing.
This needs a real device with a card in Wallet, so it can't be tried in the simulator. A short
screen recording of the setup and a tap being logged is attached: [VIDEO LINK].
Without the automation, the user can still add purchases by hand.

**Gmail (optional)**
Settings › Email Receipts › Connect Gmail. Before Google's sign-in opens, the app explains what
it reads. It uses Google OAuth in Apple's ASWebAuthenticationSession with the read-only scope
`gmail.readonly`. It searches only for receipts and bank alerts, reads them on the device, and
sends nothing anywhere except requests to Google's Gmail API. The refresh token is stored in the
Keychain. "Disconnect" revokes access with Google, and can also delete that account's purchases.
Google sign-in is only to reach the user's own email; it is not an app login, so Sign in with
Apple doesn't apply.
Test Gmail account (already has sample receipts):
- Email: [TEST GMAIL ADDRESS]
- Password: [TEST GMAIL PASSWORD]
[While Google verification is pending, Google shows an "unverified app" warning. Tap "Advanced",
then continue to Sortd. The test account above is on the allowed tester list.]

**Other things you may notice**
- Exchange rates come from frankfurter.dev (European Central Bank data). Only currency codes and
  a date are sent.
- Payment reminders are local notifications, off until the user turns them on.
- On devices with Apple Intelligence, receipts from unknown senders may be read by the on-device
  model (Foundation Models). Nothing is sent off the device for this.
- Receipt scanning (Add › Scan Receipt): uses the camera or one picked photo. Text is read on the
  device (Vision, plus the on-device model where available). The photo isn't stored or sent. The
  user checks and edits the result before it's saved. Without Apple Intelligence, simple text
  rules are used instead.
- Card digits: only the last 4 of each card and of its Apple Pay number, used to match purchases
  to cards. Never a full card number.
- Settings › Your Data has Export Purchases (CSV) and Delete All Data.
- No tracking, ads or analytics. Privacy policy: [PRIVACY POLICY URL]

Contact for review questions: [REVIEW CONTACT NAME], [REVIEW CONTACT PHONE], [CONTACT EMAIL]

---

## Before submitting

- [ ] Record the Shortcuts setup video on a real iPhone and attach it (or link it above).
- [ ] Type the real test password only into App Store Connect. Never commit it to this file.
- [ ] Create the test Gmail account, send it a few real-looking receipts, and add it as a Google
      OAuth test user. Don't use a personal account.
- [ ] Delete the square-bracket note about the unverified warning if Google verification is
      finished by then.
- [ ] Check that Settings › Apple Pay Auto-Logging still says online Apple Pay "will come from
      your email receipts in the next update" — Gmail is now in the app, so that line is out of
      date (Swift change, not part of this doc).

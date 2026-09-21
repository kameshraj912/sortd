# App Review notes — draft

Paste the "Notes" part into App Store Connect › App Review Information › Notes. Keep it under
4,000 characters. Fill in the placeholders first.

---

## Notes

Sortd is a personal spending tracker. It doesn't move, hold or manage money, doesn't connect to
any bank, and never asks for bank logins. There is no login and no Sortd account, and all data
is stored on the device. It records what the user already spent so they can see where it went.

**Quickest way to review**
On the first screen, tap "Explore with sample data". This loads about two months of sample
purchases on two sample cards. Home, Activity, Settings and each card's page are free and show
content straight away. A banner on Home says it's sample data; tap "Clear" to remove it and go
back to setup.

**Sortd Pro (in-app purchases)**
Gmail receipts, Insights, Subscriptions & Bills (with local payment reminders), the receipt
camera and category budgets are Sortd Pro. Tapping any of them shows the paywall. Three products, all unlocking the same features:
- Sortd Pro Yearly (auto-renewable, 2-week free trial for new subscribers)
- Sortd Pro Monthly (auto-renewable)
- Sortd Pro Lifetime (one-time purchase)
Buy any of them with a sandbox account to unlock Pro; the sample data then fills Insights and
Subscriptions & Bills. "Restore Purchases", Terms of Use and the Privacy Policy are on the
paywall, and Terms and Privacy are also in Settings › Privacy.
What Pro keeps giving: new receipt formats and bank layouts recognised, more currencies, and
regular feature updates. Everything is processed on the device, which is why there's no server.

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

**Gmail (optional, Pro)**
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

**Other things you may notice**
- Exchange rates come from frankfurter.dev (European Central Bank data). Only currency codes and
  a date are sent.
- Receipt scanning (Add › Scan Receipt): uses the camera or one picked photo. Text is read
  on the device (Vision, plus the on-device model where available). The photo isn't stored or
  sent. The user checks and edits the result before it's saved.
- Card digits: only the last 4 of each card and of its Apple Pay number, used to match purchases
  to cards. Never a full card number.
- Settings › Your Data has Export Purchases (CSV), Delete All Data and Privacy.
- No tracking, ads or analytics. Privacy policy: https://sortd.page/privacy

Contact for review questions: [REVIEW CONTACT NAME], [REVIEW CONTACT PHONE, +61 format], [CONTACT EMAIL]

---

## Before submitting

- [ ] Record the Shortcuts setup video on a real iPhone and attach it (or link it above).
- [ ] Type the real test password only into App Store Connect. Never commit it to this file.
- [ ] Create the test Gmail account, send it a few real-looking receipts, and add it as a Google
      OAuth test user. Don't use a personal account.
- [ ] Submit only after Google has verified gmail.readonly. Before that, reviewers can't connect
      Gmail (only listed test users can).
- [ ] Check that Settings › Apple Pay Auto-Logging still says online Apple Pay "will come from
      your email receipts in the next update" — Gmail is now in the app, so that line is out of
      date (Swift change, not part of this doc).

# App Store checklist — Sortd

Checked 19 Sep 2026 against Apple's App Review Guidelines, App Store Connect Help and Google's
OAuth docs. "Done" means built and tested in the simulator.

## Done in the app
- [x] No empty first launch: guided setup + "Explore with sample data" for reviewers (Guideline 2.1, 4.2)
- [x] Works fully offline; nothing needs an account
- [x] Delete All Data (Settings › Your Data) — wipes purchases, cards, settings, email keys, reminders
- [x] Export all purchases as CSV
- [x] In-app Privacy page + "not financial advice" note
- [x] No placeholder or personal text on screen; generic examples only
- [x] Privacy manifest `PrivacyInfo.xcprivacy`: no tracking, UserDefaults reason CA92.1
- [x] `ITSAppUsesNonExemptEncryption = NO` (only HTTPS and Apple's own encryption — Apple's page on this
      couldn't be loaded to confirm; re-check before submitting)
- [x] Light, dark and the largest accessibility text sizes checked
- [x] Debug-only tools are inside `#if DEBUG` and don't ship in release builds

## Needs you (can't be done in code)
- [ ] Apple Developer Program ($149 AUD/yr) — decide individual vs company (company hides your
      home address on the EU listing but needs a D-U-N-S number)
- [ ] A website with a **privacy policy** and **support page** (Apple and Google both need the URLs)
- [ ] Trademark check on "Sortd" (see Brand/README.md)
- [ ] EU Digital Services Act trader status in App Store Connect
- [ ] Age rating questionnaire (expected 4+)
- [ ] Screenshots: 6.9" iPhone (1320×2868), 1–10 of them
- [ ] Review notes: explain the Shortcuts automation, attach a short video, say sample data is available

## When Gmail connect is added (stage 4b)
- [ ] Ask for Gmail only when the user taps Connect, with a plain explanation first (5.1.1)
- [ ] "Disconnect Gmail" that revokes access and deletes imported data (5.1.1(v))
- [ ] Declare Google Sign-In's User ID + IP address in the App Privacy label; use GoogleSignIn 7.1.0+
- [ ] Google verification for `gmail.readonly`: homepage, privacy policy with Google's "Limited Use"
      wording, verified domain, demo video, a few weeks. Describe it as receipt "reporting".
- [ ] Until verified: max 100 test users, and they must reconnect every 7 days
- [ ] Give App Review a test Gmail account

## When receipt scanning is added (stage 5)
- [ ] Clear camera / photo library permission text
- [ ] Works on phones without Apple Intelligence (fall back to text reading only)

## When charging money
- [ ] In-App Purchase only; subscription terms and Terms of Use + privacy links in the app and listing

## Not needed for this app
- Account deletion (no Sortd accounts), Sign in with Apple (Gmail sign-in is to reach your own mail,
  not an app login), report/moderation (no content shared between users), App Tracking Transparency
  (no tracking), "must be a bank" rules 3.2.1(viii) / 5.1.1(ix) (Sortd doesn't move or manage money).

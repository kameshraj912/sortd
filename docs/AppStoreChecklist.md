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
- [ ] Apple Developer Program ($149 AUD/yr) — decide individual vs company. **Leaning company:**
      Guideline 5.1.1(ix) says apps in financial services or that "require sensitive user
      information" should be from a legal entity; reading Gmail could count. A company account
      (KV Engineering or another entity) needs a D-U-N-S number (free, ~5 business days).
      If you stay individual, explain in the review notes that Sortd doesn't move or hold money.
- [ ] Decide Gmail for v1: while Google verification is pending, public users would hit the
      "unverified app" wall (fails 2.1). Options: ship v1 without Gmail (remove the feature, not
      just hide it — 2.3.1(a)), or wait for Google verification before the App Store release.
      TestFlight with Gmail is fine (up to 100 Google test users).
- [ ] A website with a **privacy policy** and **support page** (Apple and Google both need the URLs)
- [ ] Trademark check on "Sortd" (see Brand/README.md)
- [ ] EU Digital Services Act trader status in App Store Connect
- [ ] Age rating questionnaire (expected 4+; the privacy policy says it isn't aimed at children,
      which fits 4+). Read Apple's note on Texas SB2420 before submitting:
      https://developer.apple.com/news/?id=2ezb6jhj
- [ ] Accessibility Nutrition Labels in App Store Connect (optional now, required later): claim only
      what's tested — VoiceOver, Larger Text, Dark Interface, Sufficient Contrast.
- [ ] Screenshots: 6.9" iPhone (1320×2868), 1–10 of them
- [ ] Review notes: explain the Shortcuts automation, attach a short video, say sample data is available

## Gmail connect (built)
- [x] Ask for Gmail only when the user taps Connect, with a plain explanation first (5.1.1)
- [x] "Disconnect Gmail" that revokes access and deletes imported data (5.1.1(v))
- [x] App Privacy label: "Data Not Collected". Sortd doesn't use the GoogleSignIn SDK (own OAuth via
      ASWebAuthenticationSession) and nothing reaches the developer or a partner.
- [ ] CASA security assessment: Google requires it for apps that reach data "from or through a
      third-party server". Sortd has no server (phone ↔ Google only). Say so in the verification
      form and ask Google to confirm before paying for an assessment.
- [ ] Google verification for `gmail.readonly`: homepage, privacy policy with Google's "Limited Use"
      wording, verified domain, demo video, a few weeks. Describe it as receipt "reporting".
- [ ] Until verified: max 100 test users, and they must reconnect every 7 days
- [ ] Give App Review a test Gmail account

## Receipt scanning (built)
- [x] Clear camera permission text; photo picker needs no permission
- [x] Works on phones without Apple Intelligence (falls back to text rules)
- [x] Covered in the privacy policy and review notes
- [x] AI in finance (Apple's Foundation Models rules): the user confirms scanned receipts before
      saving; Gmail purchases read by the model are marked "Read by on-device AI. Check…"

## Apple Pay taps (built)
- [x] One-field "Log Wallet Tap" action + picture guide in setup
- [x] Apple Pay number (Device Account Number) matches taps and receipts to the right card;
      required when two cards are from the same bank
- [x] ▶ test runs save nothing; unreadable taps are still saved and flagged
- [x] Old Apps Script email link removed; its saved key is cleared from phones once

## When charging money
- [ ] In-App Purchase only; subscription terms and Terms of Use + privacy links in the app and listing

## Not needed for this app
- Account deletion (no Sortd accounts), Sign in with Apple (Gmail sign-in is to reach your own mail,
  not an app login), report/moderation (no content shared between users), App Tracking Transparency
  (no tracking), "must be a bank" rules 3.2.1(viii) / 5.1.1(ix) (Sortd doesn't move or manage money).

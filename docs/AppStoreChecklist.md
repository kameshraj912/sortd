# App Store checklist — Sortd

Checked 19 Sep 2026 against Apple's App Review Guidelines, App Store Connect Help and Google's
OAuth docs. "Done" means built and tested in the simulator.

## Before any App Store build — do not skip

- [ ] **Remove `SORTD_BETA`** from `SWIFT_ACTIVE_COMPILATION_CONDITIONS` in the app target's
      Release config (`Spend.xcodeproj/project.pbxproj`). It gives Pro away free to anything
      running against the App Store sandbox, which includes TestFlight **and App Review**.
      Leave it in and reviewers never see the paywall work, and the IAPs go untested.
      Run `scripts/preflight.sh --appstore` — it fails while the flag is still there.
- [ ] Create the three products in App Store Connect and get them to "Ready to Submit".
      Until then `ProStore.load()` returns nothing and the paywall is empty.

## Knowing how it's going, without breaking the privacy promise

Sortd's whole pitch is "no tracking, nothing leaves your phone", and the
App Privacy label says Data Not Collected. Adding an analytics SDK would
make the website, the in-app privacy page and that label all false at once,
and "no tracking" is the thing this category competes on. So: don't.

Everything below comes from Apple, free, with no code and no SDK.

**Turn on (App Store Connect):**
- [ ] **App Analytics** — active devices, sessions per device, retention by
      cohort, deletions, crashes, and a territory breakdown. This is
      "how many, how much, where" and it is already anonymised and
      aggregated by Apple. It only counts users who left "Share With App
      Developers" on, so treat it as a trend, not a census.
- [ ] **Sales and Trends** — units, proceeds and refunds by day and country.
- [ ] **Payments and Financial Reports** — what actually lands in the bank.

**Watch these three numbers:**
- [ ] Refund rate. A jump usually means the paywall promised something the
      app doesn't do.
- [ ] Day-1 → Day-7 retention. The category's known killer is people giving
      up on logging, so this is the number that says whether capture works.
- [ ] Crash-free sessions.

**Fraud, and why there's little to do:**
StoreKit 2 already verifies every transaction's signature on the device
(`ProStore.swift` — `case .verified`), drops anything with a
`revocationDate`, and drops anything expired. That covers forged receipts
and "refund it but keep using it", which were the two real iOS fraud
vectors. Nothing to build.

The gap without a server is real-time refund notification (Sortd finds out
next launch), and that's it. App Store Server Notifications V2 closes it,
needs a backend, and isn't worth one until there's revenue to protect.

**The one real risk is a comped code leaking publicly.**
- [ ] Hand out different codes to different people so a leak is traceable.
      Settings shows which code unlocked that iPhone.
- [ ] If one leaks, delete it from `CompedPro.accepted` and ship an update.
      People who already redeemed it keep Pro, which is the fair outcome;
      new redemptions stop.
- [ ] There is no cross-device enforcement and there can't be without a
      server. For anything that genuinely must be single-use, use App Store
      Connect **Offer Codes** — Apple tracks redemption and each one dies
      after a single use.

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
- [ ] Apple Developer Program ($149 AUD/yr) — **decided 19 Sep 2026: individual for now.** If App
      Review cites 5.1.1(ix), switch to a company account (needs a D-U-N-S number) and resubmit.
      Review notes already say Sortd doesn't move, hold or manage money.
- [ ] Gmail for v1 — **decided 19 Sep 2026:** App Store v1 ships without Gmail; TestFlight keeps
      it (up to 100 Google test users) while Google verifies. Steps in docs/GoogleVerification.md.
      Before the App Store build: remove Gmail from that build (not just hide it — 2.3.1(a)).
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

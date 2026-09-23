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

## Money settings in App Store Connect (added 21 Sep 2026)

All three are settings, not code. Do them once the paid developer account clears.

- [ ] **App Store Small Business Program.** Apple takes 15% instead of 30% while proceeds stay
      under US$1M a year. Apply at developer.apple.com/app-store/small-business-program. It's a
      form; the lower rate starts after approval, not back-dated, so apply before launch.
- [ ] **Billing Grace Period → 28 days, "All Renewals".** App Store Connect › the app ›
      Subscriptions › Billing Grace Period. When a card fails, Apple keeps retrying and the person
      keeps Pro. `ProStore.refresh()` keeps Pro during grace (fixed 21 Sep 2026; before that it
      dropped anyone whose expiry date had passed, per Apple's currentEntitlements docs).
      `ProStoreTests.gracePeriodKeepsPro` checks grace keeps Pro, but StoreKit Testing can't
      reproduce the past-expiry case. Confirm once on TestFlight with a failing sandbox card.
- [ ] **Retention Messaging** (WWDC26). App Store Connect › Subscriptions › Retention Messaging.
      Apple shows your message, and optionally an offer, when someone taps Cancel in their
      subscription settings. No server needed. Views: message only, message + image, message +
      offer. Plan: one "message + offer" on monthly and yearly. Create a retention offer first
      (e.g. yearly at 50% off for the first year). Keep the message in the brand voice, and honest.

## Beta crash reports — Sentry (added 21 Sep 2026)

Built into TestFlight builds only (`Spend/Services/CrashReporting.swift`, `#if SORTD_BETA`).
Sends the stack trace, device model and OS. No purchases, merchants, emails, screenshots,
breadcrumbs or IP.

- [ ] Make a free Sentry account and an iOS project; paste its DSN into `CrashReporting.dsn`.
- [ ] Before the first beta build with the DSN: one line on sortd.page/privacy (beta section)
      and the beta page — "TestFlight builds send crash reports (no personal data) to Sentry."
- [ ] Crash once on purpose in a TestFlight build and check the report shows no personal data.
- [ ] **App Store build:** remove the package, or go live with it (label → Diagnostics › Crash
      Data, not linked; update the "no analytics" wording). `preflight.sh --appstore` fails
      while Sentry is linked.

## Account security (added 21 Sep 2026)

- [ ] Two-factor on every account that can touch the app: Apple Account (developer), Google
      Cloud / OAuth project, GitHub, Cloudflare (sortd.page), and the Gmail that owns them.
      Passwords from a password manager, all different.

## Compliance audit, 21 Sep 2026

Checked by hand against the rule files in github.com/mjmirza/app-store-compliance (its scripts and
hook were **not** installed or run). Guideline numbers are from that repo, not re-checked on
Apple's site.

- [x] **High · 2.3.1.** No longer applies: v1 ships with Gmail (22 Sep), so the listing and
      site can keep it. Only submit after Google verification, or Gmail won't work for reviewers.
- [x] **High · 2.1.** (Done 21 Sep: review notes rewritten with a Pro section.) Review notes say sample data fills Insights and Subscriptions & bills, but
      both are Pro. Once `SORTD_BETA` is gone the reviewer hits a lock. Add a Pro section: the
      three products, what each unlocks, and that a sandbox purchase or restore unlocks them.
- [ ] **High · 2.3.2.** Attach all three IAPs to version 1.0 and submit them with the build.
      "Ready to Submit" alone isn't enough for a first subscription.
- [ ] **Medium · 2.3.2.** Mark paid features as Pro in the listing: the promo line "See every
      subscription before it charges you" and the Insights and Recurring screenshot captions.
- [x] **Medium · 5.1.1(i).** (Done 21 Sep: Privacy Policy and Terms links on Settings › Privacy.) Pro users can't reach the privacy policy: its only link is in the
      paywall footer, which Pro users never see. Add a "Privacy Policy" link on Settings › Privacy.
- [ ] **Medium, unverified.** "Works on iPhone and Apple Watch": test a real Watch tap through the
      Wallet automation, or drop "Apple Watch" from the listing and site.
- [ ] Answer the social media question in App Store Connect ("No"). The repo says it's required
      for new versions from Sep 2026; not confirmed on Apple's site.
- [ ] App Review contact phone in international format (+61…).
- [ ] Optional: read `docs/` in that repo before each submission. Don't install its hook
      without reading the scripts first.

## Compliance pass, 23 Sep 2026 (ux-refresh branch)

Checked in code, not on a device. Not legal advice; items marked "lawyer" need one.

**App Privacy label: still "Data Not Collected".** Nothing new leaves the phone:
- [x] Setup answers (`setup.*`: goals, how you pay, feeling about spending, check-in time, spend
      abroad) are stored only on the iPhone in UserDefaults, never sent anywhere, not in backup
      files. They pick setup steps, Pro feature order and the check-in time. Editable via Settings ›
      Help & Feedback › Run Setup Again and Settings › Bills & Reminders; removed by Delete All Data.
- [x] Check-in, bill reminders and category limit alerts are local (UNUserNotificationCenter).
      No APNs, no push entitlement, no server. The check-in has fixed text and no amounts.
- [x] Quick entry with Apple Intelligence (`QuickEntryAI`, FoundationModels) runs on the device;
      output is checked against the typed line and only fills the Add form.
- [x] "Finish setup" widget check uses `WidgetCenter.currentConfigurations()`, on the device.
- [x] Only network calls in the app: Google OAuth/Gmail, frankfurter.dev, and StoreKit (Apple).
- [x] sortd.page/privacy, terms and support updated for all of the above (not deployed).
- [ ] Sentry is linked in the app target even though the DSN is empty. Its privacy manifest may
      put "Crash Data" into Xcode's privacy report and clash with "Data Not Collected". Check the
      generated report on the archive; remove the package for the App Store build (already planned).
- [ ] The in-app Privacy page (`PrivacyView` in `Views/DataControlsView.swift`) doesn't mention
      setup answers, notifications or Apple Intelligence yet. Settings › Privacy & Security now has
      a short section for them; fold it into PrivacyView when that file is free.
- [ ] Help & Feedback links `https://sortd.page/support.html`; use `https://sortd.page/support`.
- [ ] Notification permission (4.5.4): asked only after the user picks a check-in or bill
      reminders, with "Not now" beside it. Keep check-ins free of promotions (no "try Pro" text),
      or 4.5.4 needs separate opt-in consent.
- [ ] Pricing (3.1.2, ACCC): the paywall subtitle and the site lead with "$4.17 a month" for a
      yearly plan. Apple wants the billed amount most prominent. Site now says "then $49.99 a year
      (about $4.17 a month)"; check the paywall subtitle too.
- [ ] Site prices are in US dollars on a site aimed at Australia and Singapore. Lawyer: is a USD
      "guide" price OK under the ACL single-price rule, or should the site show AUD/SGD or just say
      "see the App Store"?
- [ ] Privacy policy names no person or business, only "the makers of Sortd" and an email. APP 5
      and PDPA want the identity and contact of whoever is responsible. Decide what name to show
      (the App Store will show Raj's name anyway). Lawyer: whether the small-business exemption
      means the Privacy Act applies at all, and what the PDPA DPO notice needs.
- [ ] New promise in the privacy policy: support emails are deleted on request. Confirm you're
      happy to honour it (the inbox is Gmail, via Cloudflare forwarding).

## Launch extras from web research, 21 Sep 2026

- [x] Review notes: say plainly that no money moves, no bank link, all data stays on the phone
      (5.1.1(ix) finance-entity rule). Decide whether to publish under a company instead.
- [ ] Review notes (done) and listing: what Pro keeps giving over time (3.1.2(a) "ongoing value").
- [ ] Set AU and SG prices by hand; tax forms (ABN + GST for AU; GST number for SG).
- [ ] Store page localised twice: en-AU (Australia) and en-GB (Singapore's default).
- [ ] Insights and marketing never name or recommend a card, loan, super or investment (ASIC).
- [ ] Privacy policy names a Data Protection Officer with contact details (Singapore PDPA).
- [ ] Review prompt: at most 3 a year, after a milestone (first monthly summary, 10 receipts).
- [ ] Pre-order on the App Store so sortd.page can link to a real page.

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
`revocationDate`, and only keeps subscriptions Apple reports as active or in
grace period. That covers forged receipts
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
- [x] Delete All Data (Settings › Backup & Data) — wipes purchases, cards, settings, setup answers,
      email keys, the check-in and reminders (checked in code 23 Sep 2026: it clears the whole
      UserDefaults domain, so every `setup.*` key goes)
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
- [ ] Gmail for v1 — **decided 22 Sep 2026 (replaces 19 Sep):** v1 ships **with** Gmail. Submit
      to the App Store only after Google verifies gmail.readonly (docs/GoogleVerification.md).
      Until then TestFlight only (up to 100 Google test users). `Features.gmail` / SORTD_GMAIL.
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

## Bank alerts (built, needs real emails to confirm)

Sortd reads "you just spent $X at Y" emails from 18 banks across AU, SG
and MY. This covers the card spending no merchant emails a receipt for,
and it is the only source that reports a refund.

- [x] One reader, not a regex per bank: banks change their wording, and a
      bespoke pattern per bank breaks silently when they do
- [x] An alert needs an amount **and** a merchant before it counts, so
      balances, statements, OTPs and payment-due notices produce nothing
- [x] Refunds and reversals are recorded as refunds, never as spending
- [ ] **Check against real emails.** The Standard Chartered parser was
      written against real alerts. These were written against the shapes
      alerts take. Forward one real alert from NAB and from StanChart to
      yourself, run a Gmail sync, and confirm the amount, merchant, card
      and date all land right before relying on it.

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

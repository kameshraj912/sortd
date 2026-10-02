# App Store checklist — Sortd

Checked 19 Sep 2026 against Apple's App Review Guidelines, App Store Connect Help and Google's
OAuth docs. "Done" means built and tested in the simulator.

## Before any App Store build — do not skip

- [ ] **Remove `SORTD_REPLAY`** from `SWIFT_ACTIVE_COMPILATION_CONDITIONS` in the app target's
      Release config (`Spend.xcodeproj/project.pbxproj`). Session replay is for TestFlight only.
      Run `scripts/preflight.sh --appstore` — it fails while the flag is still there.
- [ ] Create the three tip consumables in App Store Connect and get them to "Ready to Submit":
      `com.kameshraj.spend.tip.small`, `com.kameshraj.spend.tip.medium`,
      `com.kameshraj.spend.tip.large`. Raj sets the prices. Each needs one review screenshot
      of the tip sheet; attach all three to the version. Review note: tips unlock nothing.

## Money settings in App Store Connect (added 21 Sep 2026)

All three are settings, not code. Do them once the paid developer account clears.

- [ ] **App Store Small Business Program.** Apple takes 15% instead of 30% while proceeds stay
      under US$1M a year. Apply at developer.apple.com/app-store/small-business-program. It's a
      form; the lower rate starts after approval, not back-dated, so apply before launch.

## Crash reports — Sentry (added 21 Sep 2026, live app from 25 Sep 2026)

On in every Release build that has a DSN, under the same consent switch as analytics
(Settings › Privacy). `Spend/Services/CrashReporting.swift` scrubs every event before it
leaves: exception type, stack, device model and OS stay; exception text, message, request,
breadcrumbs, extra, tags and IP go. The user is the salted analytics hash only, so Crash,
Performance and Other Diagnostic Data are "linked to you" on the label (App Functionality).
Turning the switch off closes the SDK; on starts it again. Off in Debug always.

- [ ] Make a free Sentry account and an iOS project. Put its DSN in `Secrets.xcconfig`
      (`SENTRY_DSN`, see `Secrets.xcconfig.example`). Never in source; `preflight.sh --appstore`
      fails while it is empty, TestFlight only notes it.
- [ ] App Privacy label: add Crash Data, Performance Data, Other Diagnostic Data — linked to you,
      App Functionality — beside the analytics types. `PrivacyInfo.xcprivacy` already says so.
- [ ] sortd.page/privacy and the in-app Privacy page: one line, in the same release —
      "Crash reports (no purchases, merchants or emails) go to Sentry under the analytics switch."
- [ ] Crash once on purpose in a TestFlight build. In Sentry: stack and device model present;
      no IP, no merchant text; the user id is the hash (or none before sign-in).
- [ ] Not verified: whether our manifest's "linked" wins over sentry-cocoa's "not linked" in
      Xcode's privacy report on the archive. Check the report; the label is what you type anyway.

## Account security (added 21 Sep 2026)

- [ ] Two-factor on every account that can touch the app: Apple Account (developer), Google
      Cloud / OAuth project, GitHub, Cloudflare (sortd.page), and the Gmail that owns them.
      Passwords from a password manager, all different.

## Compliance audit, 21 Sep 2026

Checked by hand against the rule files in github.com/mjmirza/app-store-compliance (its scripts and
hook were **not** installed or run). Guideline numbers are from that repo, not re-checked on
Apple's site.

- [x] **High · 2.3.1.** No longer applies: Gmail was removed on 2 Oct 2026, so there is no
      hidden or dormant Gmail feature and nothing to verify with Google.
- [x] **High · 2.1.** Superseded 25 Sep: no Pro, no paywall, nothing to unlock. Review notes now
      say every feature is free (`docs/AppReviewNotes.md`).
- [ ] **High · 2.3.2.** Attach all three tip consumables to the version and submit them with the
      build. "Ready to Submit" alone isn't enough for a first in-app purchase.
- [x] **Medium · 5.1.1(i).** (Done 21 Sep: Privacy Policy and Terms links on Settings › Privacy.)
      No longer behind any paywall — nothing is locked, so the privacy policy is always reachable.
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
- [x] Only network calls in the app: Google sign-in (identity only), frankfurter.dev, and StoreKit (Apple).
- [x] sortd.page/privacy, terms and support updated for all of the above (not deployed).
- [ ] Sentry is linked and on (see Crash reports above). Check Xcode's privacy report on the
      archive shows Crash, Performance and Other Diagnostic Data as linked, matching the label.
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
- [x] Gmail — **decided 2 Oct 2026: removed from the app.** Google approves gmail.readonly only
      after a paid yearly security assessment (CASA, about US$855 a year), with no free route.
      The Google review is withdrawn (docs/GoogleVerification.md). "Continue with Google" stays
      for optional sign-in (openid and email only).
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

## Gmail (removed 2 Oct 2026)
- [x] The Gmail feature, bank-alert reading and the Google OAuth review are gone. Nothing to submit
      to Google, no test Gmail account for App Review, no "Connect Gmail" anywhere in the app.
- [x] A one-time launch clean-up revokes and deletes any saved Gmail token and the Gmail settings.
- [x] App Privacy label: nothing to add for Gmail. Sign-in with Google asks for `openid` and
      `email` only.

## Receipt scanning (built)
- [x] Clear camera permission text; photo picker needs no permission
- [x] Works on phones without Apple Intelligence (falls back to text rules)
- [x] Covered in the privacy policy and review notes
- [x] AI in finance (Apple's Foundation Models rules): the user confirms scanned receipts before
      saving.

## Apple Pay taps (built)
- [x] One-field "Log Wallet Tap" action + picture guide in setup
- [x] Apple Pay number (Device Account Number) matches taps and receipts to the right card;
      required when two cards are from the same bank
- [x] ▶ test runs save nothing; unreadable taps are still saved and flagged
- [x] Old Apps Script email link removed; its saved key is cleared from phones once

## When charging money
- [ ] In-App Purchase only; subscription terms and Terms of Use + privacy links in the app and listing

## Not needed for this app
- Account deletion (no Sortd accounts), Sign in with Apple (sign-in is optional; nothing needs it), report/moderation (no content shared between users), App Tracking Transparency
  (no tracking), "must be a bank" rules 3.2.1(viii) / 5.1.1(ix) (Sortd doesn't move or manage money).

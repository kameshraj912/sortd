# Beta playbook — Sortd on TestFlight

Written 22 Sep 2026 for a first-time TestFlight run. Plain steps, in order. Every fact below has
the official source next to it. Where I couldn't find an official Apple page for something, it
says **not confirmed** — check that yourself before relying on it.

This is the A-to-Z. For "is this build safe to upload", run `scripts/preflight.sh` first (or
`scripts/preflight.sh --appstore` before the real App Store build — see
`docs/AppStoreChecklist.md`).

## 1. The two kinds of tester

**Internal testers** — people with a role on your App Store Connect team (Account Holder, Admin,
App Manager, Developer or Marketing). Up to **100** of them. No review needed — a build reaches
them the moment it finishes processing. Each person can use it on up to **10 devices** on their
Apple Account.
Source: [Add internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/)

**External testers** — anyone else, invited by email or a public link, in groups you create. Up
to **10,000 people** total. Their first build of a new version needs **Beta App Review** (below).
Source: [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)

**Practical read for Sortd:** start on internal testers (you, and anyone you add to the team) —
no review, no waiting. Move to an external group once you want friends who aren't on the team, or
the public sortd.page beta form.

## 2. Public link

An external group can turn on a public link — anyone with it can join without an individual
invite, up to a tester cap you set (1–10,000, and you can lower it later or turn the link off
once you've got enough people). Same external-tester limits and Beta App Review rules apply as
above.
Source: [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/) (the 10,000-person cap is stated here; the exact public-link screen mechanics are **not confirmed** by a page I could fully read — the underlying limit is Apple-documented, the click path might have moved).

## 3. Beta App Review

- Internal testers: never reviewed.
- External testers: the **first build of each new version** needs full Beta App Review before
  external testers see it. Later builds of the *same* version can skip review.
- You can submit up to **6 builds** for review in a 24-hour period, and only **one build per
  version** can be in review at a time.
Source: [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)

**Turnaround time:** Apple doesn't publish one. **Not confirmed** — developer-forum reports range
from under a day to a few days. Plan the first external build a few days ahead of when you want
people using it.

## 4. Build expiry

A build is testable for **90 days** after upload, then it stops working for testers. Apple's own
words: "You can test a build for up to 90 days... Your build becomes unavailable for testers after
90 days." Upload a new build before that, and each new build gets its own fresh 90 days.
Source: [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

## 5. Test Information — what to fill in, and ready-to-paste text for Sortd

App-level fields (App Store Connect → your app → TestFlight tab → Test Information):

- **Beta App Description** — required.
- **Feedback Email** — required in effect (it's how testers on older TestFlight versions reach
  you, and it's the reply-to address on invite emails).
- **App Information** checkbox — optional, on by default; shows your approved App Store
  screenshots and category alongside the beta.
Source: [Provide test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/)

Separately, **What to Test** is entered per build, when you add that build to a group — it's not
the same screen as the description above.

I could not confirm from an official TestFlight-specific page whether **Marketing URL** or
**Privacy Policy URL** live on this exact screen — **not confirmed**. Your Privacy Policy URL is
definitely required elsewhere in App Store Connect (General App Information, used for both
TestFlight and the App Store listing), so set it once there: `https://sortd.page/privacy`.

**Ready to paste:**

- **Beta App Description:**
  > Sortd tracks what you spend, on your iPhone. No bank login, no account, nothing leaves your
  > phone except what you choose to connect. Log Apple Pay taps automatically with a Shortcuts
  > automation, scan a paper receipt, or connect Gmail (read-only) to catch email receipts and
  > bank alerts. See where the money goes by day and by category, in AUD, SGD and other
  > currencies. This TestFlight beta unlocks every Pro feature for free while you test.

- **What to test (first build):**
  > Set up the Apple Pay Shortcuts automation (Setup Guide in the app) and make a real tap.
  > Connect Gmail if you use it, and check receipts come through right. Scan a paper receipt.
  > Add a purchase by hand. Check multi-currency conversion if you spend outside AUD. Try
  > Insights, budgets and Subscriptions & bills — Pro is unlocked for this beta. Send feedback
  > (screenshot + comment) for anything wrong, and let a crash happen if it happens — it's
  > reported automatically.

- **Feedback Email:** `support@sortd.page`
- **Privacy Policy URL:** `https://sortd.page/privacy`
- **Sign-in note (for the description or What to Test, if there's room):** "No sign-in required —
  Sortd works fully offline. Gmail is optional."

## 6. Export compliance

Apps that only use encryption "built into the operating system" — HTTPS via `URLSession`, the
Keychain — are **exempt**, and don't need to upload export documentation. Sortd's Info.plist
already sets `ITSAppUsesNonExemptEncryption = NO` (checked in `Spend.xcodeproj/project.pbxproj`,
Release config), which is the correct answer for an app that only does HTTPS and Apple's own
crypto — nothing custom, nothing proprietary.
Source: [Complying with Encryption Export Regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)

One wrinkle: Apple's page notes that even an **exempt** app might still need a **year-end
self-classification report** filed with the US government directly (not through Apple) — this is
a US export-control (BIS) requirement, separate from anything in App Store Connect. **Not
confirmed** whether Sortd specifically needs to file one — that's a US export-law question, not
an App Store one; worth 20 minutes with the BIS page below or an accountant if this ever earns
real revenue.
Source: [BIS Annual Self-Classification Report](https://www.bis.doc.gov/index.php/policy-guidance/encryption/4-reports-and-reviews/a-annual-self-classification)

Because the Info.plist key is already set, App Store Connect / Xcode should skip asking the
export-compliance question again on upload. If it's ever asked anyway: the correct answer for
Sortd is "No" to using non-exempt encryption (it only uses HTTPS and standard Apple encryption).

## 7. How testers send feedback, and where you read it

In TestFlight, a tester can send a **screenshot with a comment**, or Sortd itself can trigger a
**crash report with a comment**. You read both in App Store Connect: your app → **TestFlight tab
→ Feedback → Screenshots** or **Crashes**, filterable by build, version, device and OS. Crash
reports are downloadable for **120 days**.
Source: [View tester feedback](https://developer.apple.com/help/app-store-connect/test-a-beta-version/view-tester-feedback/)

This is on top of, and separate from, the Sentry crash reports Sortd sends directly (see
`docs/AppStoreChecklist.md` and `site/privacy.html`) — Sentry gets the crash itself with no
comment; TestFlight is where a tester can add "this happened when I tapped X".

## 8. In-app purchases on TestFlight

All purchases in TestFlight use Apple's **Sandbox** — nothing is charged, real or otherwise.
Subscriptions renew on an accelerated schedule for testing (the default is **1 real month =
5 minutes**; there's a table of faster/slower speeds you can pick per Sandbox tester in App Store
Connect), and a subscription **auto-renews up to 12 times** after the first purchase before
Apple turns off further auto-renewal on the 13th attempt — so you can watch a full
subscribe-renew-lapse cycle without waiting months.
Sources: [Testing an auto-renewable subscription](https://developer.apple.com/documentation/storekit/testing-an-auto-renewable-subscription) ·
[Manage Sandbox Apple Account settings](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings/)

A Sandbox Apple Account is treated as inactive if it hasn't completed a purchase in **180 days**.
Same source as above.

Practically: `SORTD_BETA` already gives testers Pro for free (see `ProStore.swift`), so you may
not need to test real Sandbox purchases much during the beta itself — but it's worth buying each
plan once in Sandbox before the App Store build, to see the real StoreKit UI and confirm pricing
displays correctly.

## 9. Tester recruitment and cohorts

Apple publishes no guidance on cohort size or recruitment — **not confirmed / not an Apple
source**, this is just a reasonable plan:

- **Week 1:** ~10 people you know (friends, family) as internal or a small external group. Fast
  feedback loop, easy to reach them directly if something breaks.
- **Week 2 onward:** open the public link, point the sortd.page beta sign-up form at it, and grow
  toward 50–100 testers as sign-ups come in. Keep the public-link cap a bit above where you
  actually are, so it doesn't quietly close early.
- Don't feel pressure to hit 10,000 — a spending tracker learns more from 50 engaged testers
  giving real feedback than from 5,000 silent installs.

## 10. What to track, weekly

- **Crash-free sessions.** Sentry's dashboard once a DSN is set (see the exact setup steps
  wherever this task was reported), and/or App Store Connect's own crash count under App
  Analytics.
- **Onboarding completion.** Not currently instrumented — there's no built-in funnel for "started
  setup → finished setup". **Not built**; if this matters, the honest options are asking testers
  directly, or building a small local counter (which would need its own privacy-page update).
- **Apple Pay tap success.** `AppStoreChecklist.md` already notes unreadable taps are saved and
  flagged rather than dropped — check those flagged entries by hand for now; there's no reporting
  view yet.
- **Top feedback themes.** TestFlight's Feedback tab (screenshots + crashes) plus whatever comes
  to `support@sortd.page`. Skim both weekly and write down the two or three things that came up
  more than once.

## 11. Weekly release routine

- **Build number:** every upload needs a strictly higher `CURRENT_PROJECT_VERSION` than the last
  one — `scripts/preflight.sh` reminds you of the current number, it doesn't bump it for you.
- **Changelog / "What to Test":** update the per-build What to Test field (see §5) each time,
  even if it's one line — "fixed the Gmail reconnect bug" tells testers what to actually check.
- **Before every upload:** `scripts/preflight.sh` (plain, for TestFlight). It checks `SORTD_BETA`
  is on, warns about the build number, checks for huge tracked files, and fails if a DEBUG-only
  flag (`SPEND_DEMO`, `SPEND_PRO`, `SPEND_PAYWALL_DEMO`, `SPEND_REEL_TAP`) leaked outside
  `#if DEBUG`.

## 12. Bug triage

A simple order, cheapest to say hardest to ignore:

1. **Crashes** — Sentry stack trace (once set up) plus TestFlight's own crash feedback. Fix these
   first; nothing else matters if the app doesn't stay open.
2. **Data loss or wrong numbers** — anything that loses a purchase, double-counts, or gets a
   currency conversion wrong. Fix before the next build ships.
3. **Broken feature** — something doesn't work but doesn't lose data (a screen that won't open, a
   button that does nothing).
4. **Cosmetic / wording** — everything else. Batch these into whichever build has room.

Keep a running list (even a plain note) of what's open, what build it was seen in, and what build
fixed it — that becomes the changelog for the next "What to Test".

## 13. Before public launch — checklist

- [ ] **Remove `SORTD_BETA`** from the Release config and confirm with
      `scripts/preflight.sh --appstore` — it must exit clean. See `docs/AppStoreChecklist.md`.
      This also turns Sentry off for good in the shipped App Store build (`CrashReporting.swift`
      only compiles in under `SORTD_BETA`).
- [ ] **Google verification / CASA status** — check where it landed. Details in
      `docs/GoogleVerification.md`.
- [ ] **App Privacy label** — while the beta is live and Sentry is on, the honest label includes a
      **Crash Data** entry (used for App Functionality, not linked to your identity — see the
      privacy options in `CrashReporting.swift`). Once `SORTD_BETA` is removed for the public
      build, Sentry compiles out entirely and the label can go back to Data Not Collected, matching
      `docs/AppStoreChecklist.md`.
- [ ] **App Store Small Business Program** — cuts Apple's commission from 30% to **15%** on paid
      apps and in-app purchases if total proceeds are under **$1,000,000 USD** in the trailing 12
      months. Enroll as the Account Holder, after accepting the current Paid Apps Agreement.
      Source: [App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/)
- [ ] **Offer codes ready** — see `docs/ProAndPayments.md` for how to create them; have a first
      batch ready so you can hand out free Pro the day the app goes live, not scramble for it.

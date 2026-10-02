Sortd Money — Privacy Policy 2 Terms 2 in-app copy for usage analytics, crash reports and beta session recordings

Written 26 Sep 2026, for whoever edits `site/privacy.html`, `site/terms.html`,
`Spend/Views/DataControlsView.swift`, `Spend/PrivacyInfo.xcprivacy` and
`docs/TestFlightWhatToTest.md`. This file is a draft only. Nothing here is posted, sent
or deployed by writing it.

**Read before using this:** two facts in this brief don't match what I found in the
worktree's code. Both are flagged again at the end, but read them first:

1. **Session replay is OFF in code today, unconditionally.** `Spend/Services/Analytics.swift`
   sets `config.sessionReplay = false` with no beta/live branch, and
   `docs/specs/2026-09-25-free-app-overhaul-2-analytics.md` records "**Session replay: off**"
   as Raj's decision on 25 Sep. There is also no `SORTD_BETA` flag any more (`CLAUDE.md`:
   "`SORTD_BETA` is gone") to hang a beta-only switch off. The copy below is written as
   instructed — beta screens recorded, masked — but **this needs code before it's true**,
   most likely a remote PostHog setting or a small `Bundle.main` check rather than a new
   compile flag. Don't ship this copy before someone flips that switch and an audit test
   (like the "autocapture audit" the spec already plans for element interactions) confirms
   the masking actually holds fields, amounts and emails back.
2. **PostHog's own default host is EU, not US.** `PostHogSink.defaultHost` is
   `https://eu.i.posthog.com` (`Spend/Services/Analytics.swift:314`), and the analytics spec
   says "Host: PostHog EU … unless Raj picks US." The actual `POSTHOG_HOST` value lives in
   the gitignored `Secrets.xcconfig`, which I can't read. I've written "US" below because
   that's the fact I was given, but **Raj should confirm the real project region** before
   this goes on the privacy page — EU vs US changes what "Where data goes" honestly says.

## Research: how other apps word this (read 26 Sep 2026)

- **Copilot Money** (`copilot.money/privacy-policy`): "We may use third-party analytics
  services (such as Google Analytics and Amplitude Analytics) on our Services to collect and
  analyze usage information through cookies and similar technologies," and separately, crash
  data is used to "understand and resolve app and other crashes and other issues being
  reported." No session-replay tool is named. Plain, short, names the vendor by name — the
  model I followed below.
- **Monzo** — a third-party bug report (`github.com/daintreehq/daintree/issues/12405`, read
  26 Sep 2026) describes Monzo's own privacy text as telling users "a roughly 10% sample" of
  crash reports goes to Sentry, while the shipped code didn't sample at all. The lesson for
  Sortd: the number in the policy has to match what `CrashReporting.swift` actually does
  (`enableAutoSessionTracking = true`, no sampling set), not a rounder or softer figure.
- **PostHog's own docs** (`posthog.com/docs/session-replay/privacy`, `posthog.com/pocket-guides/session-replay/protecting-user-privacy`,
  read 26 Sep 2026): PostHog masks input fields and text by default in session replay, and
  says masked data "is never sent over the network." That's the standard I used for "covered
  up before it leaves your phone" below — check that our config actually turns masking on
  when replay ships; PostHog's own default masks text, but the app's exact config value is
  what will actually run.
- **Sentry** (`docs.sentry.io/security-legal-pii/security/data-retention-periods`, read 26 Sep
  2026): errors are kept 30 days on Sentry's Developer plan, 90 days on Team/Business —
  Sortd's own plan tier is **not verified**, so the retention line below says "30 to 90 days."
- I could not find a public Sortd-comparable app (YNAB, Monzo full text, Notion, Linear) that
  names PostHog specifically with a quoted sentence about session replay; the Copilot and
  PostHog-docs quotes above are the closest real wording I could confirm and cite.

## 1. Privacy Policy additions (site/privacy.html)

Voice match: the existing page has no jokes, short plain sentences, "we"/"you". Kept that;
this isn't post/caption copy.

### Usage data

> Sortd sends usage data to PostHog, a company in the US, so we can see which parts of the
> app people use and where they get stuck. It's on by default. Turn it off any time in
> Settings › Privacy.
>
> **What we send:** named events like "purchase added" or "setup finished," which screen
> you're on, your phone model, your iOS version, the app version, and a scrambled (hashed)
> id that stands in for you. The hash can't be turned back into your Apple or Google
> account, your name or your email.
>
> **What we never send:** amounts, shop names, notes or card numbers. A filter on your phone checks every event before it leaves and drops anything that
> looks like money or an email address, even if that means the event goes out missing a
> detail.

### Crash reports

> If Sortd crashes, it sends a report to Sentry, another US company, so we can find and fix
> the bug. This shares the same on/off switch as usage data.
>
> A crash report has the type of error, where in the code it happened, your phone model and
> iOS version, and the same scrambled id. We strip the error's own text first, because an
> error message can sometimes carry a shop name or a piece of an email. No screenshot, no
> list of your recent taps, and no internet address.

### Session recordings (beta) — do not publish until the code matches (see note above)

> While Sortd is in TestFlight only, PostHog also records a screen video of what testers do,
> so we can see exactly where the app confuses people, not just that it did. Every text
> field, amount, shop name and email on screen is covered with a solid box before the
> recording ever leaves your phone. This stops automatically once Sortd leaves TestFlight,
> and the same Settings › Privacy switch turns it off any time before that too.

### Your choices

> One switch — Settings › Privacy — turns off usage data, crash reports and, during the
> beta, screen recordings, all together. Turning it off stops new data going out. It doesn't
> reach back and erase what's already been sent; for that, see "Asking us to delete it"
> below.

### Where data goes

| Goes to | What | Kept where | Why |
|---|---|---|---|
| PostHog | Usage events, hashed id, device model, app version, (beta only) masked screen recordings | US servers | Analytics — see where people get stuck |
| Sentry | Crash reports, hashed id, device model, app version | US servers | Find and fix bugs |
| Apple iCloud | An encrypted copy of your purchases, only if you turn on Back up to iCloud | Your own private iCloud database | So losing your phone doesn't lose your data |
| Apple | Sign in with Apple hashed id; App Store purchase check | Apple's servers | Signing in, checking Sortd Pro |
| Google | Sign in with Google hashed id (identity only: openid and email) | Google's servers | Signing in |

*(Regions above are as given to me for this draft. See the code-vs-brief flag at the top —
confirm PostHog's actual region before publishing.)*

### How long they're kept (not verified — set in each company's account, not in Sortd's code)

- **PostHog:** usage events are kept for as long as our plan allows; the exact number
  depends on the plan Raj has picked and isn't in this worktree. Session recordings default
  to 30 days on PostHog's free plan, longer on paid ones
  ([PostHog retention docs](https://posthog.com/docs/session-recording/data-retention), read
  26 Sep 2026).
- **Sentry:** 30 to 90 days depending on plan
  ([Sentry retention periods](https://docs.sentry.io/security-legal-pii/security/data-retention-periods),
  read 26 Sep 2026). Sortd's own plan tier is not verified.

### Asking us to delete it

> Email support@sortd.page and ask us to delete your PostHog and Sentry data, with roughly
> when you used Sortd. If you're signed in, deleting your account (Settings › Sign-in ›
> Delete Account) deletes your PostHog person automatically — a small Cloudflare function
> does this the moment you delete, using a key that never lives in the app itself. Sentry
> doesn't have that same automatic delete yet: your crash data there ages out on its own (see
> "How long they're kept" above).

*Australian and Singapore users:* Sortd is run from Australia. Complaints can go to the
Office of the Australian Information Commissioner under the Privacy Act 1988 (Cth), or in
Singapore, the Personal Data Protection Commission under the PDPA — the page already links
both regulators near the bottom. **Not verified:** whether the Privacy Act 1988 (Cth) even
applies to Sortd as a small business (the small-business exemption turns on annual turnover);
say so plainly to a lawyer before leaning on the Act's name for anything beyond "you can
complain to the OAIC."

## 2. Terms of Use additions (site/terms.html)

### Beta testing (TestFlight)

> **Beta testing (TestFlight)**
> Sortd in TestFlight is a beta. Things can break, a screen can look unfinished, and a build
> can be pulled without notice. While you're testing, PostHog may record a screen video of
> what you do in the app, with amounts, shop names, emails and anything you type covered up
> — see the Privacy Policy. Testing is free: TestFlight doesn't charge you anything, and the
> tip jar in Settings › About stays optional and unlocks nothing, in beta or after.

Slot: a new H2 after "Check your bank statements" and before "Provided 'as is'."

### Sign in with Apple / Google — one sentence for the existing "Your part" section

> If you sign in with Apple or Google, we keep a scrambled (hashed) version of your account
> id — never your name or email — so Sortd can tell it's the same you across devices without
> holding your real identity itself.

## 3. In-app text

### The usage-data switch (DataControlsView.swift, PrivacyView) — two variants, both under 40 words including the title

**Variant A — short, matches the existing tone**
Title: "Share usage & crash data"
Footer: "Counts and crashes, never amounts. In beta, screens are recorded with amounts and names covered up. Turn off anytime."
(19 words in the footer, 24 with the title.)

**Variant B — a little more explicit about the beta part**
Title: "Share usage & crash data"
Footer: "Helps us see what's broken. Never your amounts or shop names. During the TestFlight beta, screens are recorded with anything sensitive masked out. Off anytime."
(29 words in the footer, 34 with the title.)

Pick A once the beta note only needs a passing mention; B if App Review or a tester needs the
masking spelled out. Either way, **don't ship until session replay is actually wired up** —
see the flag at the top. Until then, keep the current line: "Usage counts, never amounts.
Turn off anytime."

The row above the switch currently reads "Crash reports have no purchase data" — a small
tightening to match, optional: "Crash reports never carry amounts or shop names."

### TestFlightWhatToTest.md — two lines to add under "Also worth a look"

> Sortd records a masked screen video during this beta (Settings › Privacy has the switch),
> so we can see where testers get stuck. Amounts, shop names, emails and anything typed are
> covered up before it ever leaves your phone.

## 4. App Privacy label answers (App Store Connect) — checklist

Cross-checked against `Spend/PrivacyInfo.xcprivacy`, which already declares these six as
linked, not tracking:

| Data type | Collected | Linked to user | Used for tracking | Purposes | Why |
|---|---|---|---|---|---|
| Product Interaction | Yes | Yes | No | Analytics, App Functionality | PostHog's named events (e.g. "purchase added") show where people get stuck |
| User ID | Yes | Yes | No | Analytics, App Functionality | The salted hash ties events to one person across sessions and reinstalls, without a name or email |
| Device ID | Yes | Yes | No | Analytics, App Functionality | PostHog and Sentry group events and crashes by device model |
| Crash Data | Yes | Yes | No | App Functionality | Sentry tags crashes with the same hash (`setUser`) so a fix can be confirmed for that person |
| Performance Data | Yes | Yes | No | App Functionality | Sentry's session tracking gives the crash-free rate |
| Other Diagnostic Data | Yes | Yes | No | App Functionality | Matches the manifest today; the app scrubs these fields to empty before sending, but the type is still declared |
| Coarse Location | No | — | — | — | Only true if Raj has turned on "Discard client IP data" in the PostHog project — **not verified** whether that's been done |
| Photos or Videos / screen content (beta) | **Not yet answered** | — | — | — | Apple's data-type list has no exact "screen recording" category; whether the beta replay needs its own declared type is **not verified** — get Apple's current guidance and a second opinion before submitting, and only once the feature actually ships |
| Financial Info, Contacts, Health, etc. | No | — | — | — | Unchanged; nothing here touches these |

Tracking (the top-level toggle): **No** for the whole app — no ATT prompt, no ad network, no
data broker, matching `NSPrivacyTracking = false` in the manifest.

## 5. Exact places to change

- **`site/privacy.html`**
  - Line 44 "Last updated" date.
  - The "In short" table, the "Analytics, ads, tracking" row (currently "None") — no longer
    true.
  - Line 83: "...Sortd has no analytics, ads, crash-reporting or tracking tools, and does not
    share or sell data." — false now, remove or rewrite.
  - New H2s, likely after "How we protect your data": Usage data, Crash reports, Session
    recordings (beta), Your choices, Where data goes, retention line, deletion line — all
    drafted above.
  - Line 159: "...Sortd has no analytics, crash-reporting, advertising or tracking tools
    built in." — false now, rewrite alongside the Services list.
  - "How long Sortd keeps data" section (~165-175): add PostHog/Sentry retention bullets.
  - "Your controls" section (~177-183): add the "ask us to delete PostHog/Sentry data"
    bullet.
- **`site/terms.html`**: new "Beta testing (TestFlight)" H2 (slot given above), plus the
  sign-in sentence in "Your part."
- **`Spend/Views/DataControlsView.swift`**: the `Toggle` label's `Text("Share usage data")`
  and its subheadline `Text("Usage counts, never amounts. Turn off anytime.")` (lines 26-28);
  optionally the `row("ladybug", "Crash reports have no purchase data")` text (line 35) and
  the `.accessibilityHint` (line 34).
- **`Spend/PrivacyInfo.xcprivacy`**: the top comment (lines 5-16) should note the beta
  recording once it ships; whether a new declared data type is needed for it is not
  verified (see checklist above).
- **Also found, outside the brief's file list, worth flagging:** `docs/AppStoreListing.md`
  line 54, "No ads, no analytics, no trackers." — this is now false and visible to strangers
  in the live description. I did not edit it (out of scope for this file), but whoever owns
  that file should know. `docs/AppReviewNotes.md` (line 65) already reads correctly — no
  change needed there.

## Not verified (collected in one place)

- Session replay is off in code, unconditionally, with no beta/live branch — see the flag at
  the top. This whole "Session recordings (beta)" section describes an intended feature, not
  a shipped one.
- PostHog's actual project region (EU per code default vs. US per this brief) — the real
  value is in gitignored `Secrets.xcconfig`, unreadable here.
- Sortd's actual PostHog and Sentry plan tiers, and so the exact retention windows.
- Whether Raj has turned on PostHog's "Discard client IP data" setting (needed for the
  Coarse Location "No" answer to hold).
- Whether the Privacy Act 1988 (Cth) applies to Sortd given the small-business turnover
  exemption.
- Whether Apple's App Privacy taxonomy needs a distinct data type for the beta screen
  recording, and whether TestFlight builds even show the App Privacy label the same way a
  public listing does.
- Character/word counts above were counted by hand, not run through a tool — recount before
  use, especially the two switch-copy variants.

# Overhaul 2: usage analytics with PostHog, tied to the user (25 Sep 2026)

Part of `2026-09-25-free-app-overhaul-overview.md`. Crash reports are in `2b`.
**Raj decided on 25 Sep:** PostHog, full tracking, tied to the user. Session replay off. Feature flags on. On by default, with a switch. Runs in TestFlight and in the live app.

## Problem

Raj: "Since it is free, let's actually track and record important data about the app users."

Today we cannot see whether setup works, or where people stop. `docs/AppStoreChecklist.md` decided "don't add analytics", to keep the label at Data Not Collected. That decision is now reversed. Every "no analytics" line in the app and in `docs/` must be rewritten.

## What was decided, and why the alternatives lost

| | PostHog, identified (decided) | TelemetryDeck, anonymous | Firebase |
|---|---|---|---|
| Per-user funnels, cohorts, support lookup | yes | per install only; no lookup | yes |
| Feature flags / A-B | yes (1M requests/mo free) | not verified | Remote Config |
| Label | Product Interaction, User ID, Device ID: **linked to you** | not linked | linked |
| Free tier (read 25 Sep) | 1M events/mo | 50k signals/mo for new accounts | not checked |

## What comparable apps declare (App Store "App Privacy", US store, read 25 Sep 2026)

I did not check which SDKs these apps use. The labels below are summaries of each page, as the fetch tool returned them.

| App | Product Interaction | Identifiers | Crash Data | Notes |
|---|---|---|---|---|
| [Copilot Money](https://apps.apple.com/us/app/copilot-track-budget-money/id1447330651) | linked | linked (App Functionality) | **not linked** | Financial Info linked |
| [Monarch](https://apps.apple.com/us/app/monarch-budget-track-money/id1459319842) | linked | linked | **linked** (Other Purposes) | no "not linked" section |
| [YNAB](https://apps.apple.com/us/app/ynab/id1010865877) | linked | User ID, Device ID linked | **linked** (Analytics, App Functionality) | everything linked |
| [Spendee](https://apps.apple.com/us/app/expense-budget-app-spendee/id635861140) | linked | Device ID, User ID linked | **not linked** | |
| [Buddy](https://apps.apple.com/us/app/buddy-budget-planner-app/id936422955) | linked | User ID linked; Identifiers used to track | **not linked** | uses tracking |
| [Flighty](https://apps.apple.com/us/app/flighty-live-flight-tracker/id1358823008) | linked | User ID linked | not listed | |
| [Endel](https://apps.apple.com/us/app/endel-focus-sleep-sounds/id1346247457) | linked | User ID linked; Device ID not linked; Identifiers used to track | not linked (the summary was unclear; it may also be linked) | |

- **The norm:** Product Interaction and a User ID are linked in all seven. Crash Data is split: not linked in 3 or 4 apps, linked in 2, not listed in 1.
- **Sortd's label:**
  - Product Interaction, User ID and Device ID: linked; purposes Analytics and App Functionality.
  - Crash, Performance and Other Diagnostic Data: linked, because 2b calls `setUser` (like YNAB and Monarch).
  - Tracking: none. Sortd would then be the only one of these with no Financial Info at all.
- **An option Raj can take in 2b:** skip `setUser`, and Crash Data stays "not linked", like Copilot, Spendee and Buddy.

## Design

**Identity:**
- Before sign-in, PostHog's anonymous distinct ID serves as the per-install ID.
- At sign-in (sub-spec 4): `identify(sha256(appSalt + provider + subject))`. Never the email or name.
- PostHog's docs say identify "merges the anonymous person into the identified person". So call **identify**, and alias only if a second ID ever has to be joined.
- Sign-out or delete: `reset()`.

**Person profiles:** `.always`, instead of the default `.identifiedOnly`, so users have a profile before sign-in. The cost impact is **not verified**.

**Capture:**
- Lifecycle events: on (default).
- Screen views: `.postHogScreenView()` on each tab root.
- The named events below.
- `captureElementInteractions`: **on only after an audit.** VoiceOver labels speak amounts and merchants (`Money.spoken`), and some text comes from receipts. Sensitive views get `ph-no-capture`; PostHog documents that tag for replay, and whether it also covers autocapture is **not verified**.

**Session replay: off.**

**Feature flags:**
- On, with `preloadFeatureFlags`.
- Only for A/B tests between shipped, reviewed screens. Never to switch on hidden features (guideline 2.3.1, per the note in `Features.swift`).

**Host:** PostHog EU (`eu.i.posthog.com`), unless Raj picks US.

**Consent:**
- On by default. Settings › Privacy & Security gets "Share usage and crash reports".
- Turning it off calls `optOut()` and stops Sentry.
- The state and date are stored on the device.
- One line on the setup privacy card.
- Lawyer: whether EU users need opt-in.

## Events (never amounts, merchants, emails, card digits or notes)

The names below are the `Analytics.Event` raw values, pinned by `SpendTests/AnalyticsTests.swift` (updated 25 Sep 2026 to match the code; the earlier draft names are gone).

- `setup_started(rerun)`, `setup_step_viewed(step, index)`, `setup_step_completed(step, index, skipped)`, `setup_finished(skipped, steps_seen)`. `step` is the `SetupFlow.Step` case name (`welcome`, `account`, `goals`, …); the optional `.account` step (sub-spec 4, on with `SORTD_SIGNIN`) adds a `choice` property to its own `setup_step_completed`: `apple`, `google` or `guest` — never which provider's sheet failed, just how the person got past the step
- `activation_first_auto_purchase(source: tap|email, hours_bucket)`: once per install, never on sample data or a test tap
- `tab_opened(tab)`: the first tab at launch included
- `purchase_added_manually(category_changed, has_note)`
- `purchase_deleted(count)`, `purchase_undone(count)`
- `apple_pay_tap_logged(merged)`
- `backup_completed`, `restore_completed(mode)`
- `tip_left(size: small|medium|large)`: never the price
- `tip_shown(id)`, `tip_used(id)`: in-app tips (sub-spec 7). `id` is the tip's `TipCopy` id (`apple_pay`, `swipe`, `search`, `insights`, `month`); shown once per tip per install, used once when the thing the tip was about is done after it was shown
- `intro_shown`, `intro_finished(skipped, step)`: the three-step app intro (`docs/specs/2026-09-25-app-intro.md`). `intro_shown` once per showing (a fresh install or a Help replay); `intro_finished` once per showing when it ends, `step` is the 0-based step it ended on
- `analytics_opted_out`: sent once, then nothing. The switch and the date it was flipped are kept on the phone (`analyticsEnabled`, `analyticsConsentChangedAt`) and survive Delete All Data.
- `signed_in(provider: apple|google)`, `signed_out`: sign-in (sub-spec 4) also calls `identify` (before `signed_in`) and `reset` (after `signed_out`). Never the email or the subject.
- `founder_note_seen(moment: aha|about)`: the founder's note (`FounderNoteSheet`), sent each time it is shown — at the aha moment (once ever, right after `ActivationCard`'s celebration) or replayed from Settings › About. `founder_note_reply_tapped`: the "Tell Kameshraj" button, before its mailto opens.

### Beta additions (26 Sep 2026): more intent events, session replay, the developer menu

Session replay: on only in a `SORTD_REPLAY` build (the beta), off for the App Store release,
following the same `Analytics.isEnabled` switch (`PostHogSDK.optOut()` uninstalls the replay
integration, `optIn()` reinstalls it). `screenshotMode` (SwiftUI needs it, not the wireframe
mode), all text inputs, images and sandboxed views masked by default, and `.postHogMask()` on
top of that for the big amount on Home, `TransactionRow`'s amount and shop, the transaction
detail amount/shop/note. Throttled to about one screenshot a
second (`sessionReplayConfig.throttleDelay`).

New events, never amounts or merchant/shop names:

- `search_used`: the first character typed into Activity search, once per session (in-memory; a relaunch is a new session)
- `receipt_scanned(success)`: the camera scan finished, whether or not it read a total
- `statement_imported(rows)`: a CSV/PDF/screenshot import finished; `rows` is the count found
- `budget_set`: the monthly budget sheet's Save button, no amount
- `category_limit_set(category)`: a category's monthly limit sheet's Save button; `category` is the `SpendCategory` name, never the limit
- `insights_range_changed(range)`: the Home chips, `range` is `1W`, `1M` or `3M`
- `day_stepped(direction)`: the Activity day pager's chevrons, `direction` is `newer` or `older`
- `purchase_edited(field)`: the transaction detail screen commits a changed amount or shop name; `field` is `amount` or `shop`, never the value
- `category_changed(from, to)`: a purchase's category changed after it was logged (Activity swipe/long-press, or the detail screen); both are `SpendCategory` names
- `card_added`: Settings › Cards' New Card sheet saves a card that did not exist before
- `app_lock_turned_on`: the Face ID/Touch ID lock is turned on, after the authentication check passes
- `help_opened`: Settings › Help & Feedback appears
- `developer_test_event(sent_at)`: the hidden developer menu's "Send test event" (Settings › About, tap the version 7 times in 3 seconds)

The developer menu (`Spend/Views/Settings/DeveloperMenuView.swift`) also has "Send test report
to Sentry" (a forced, scrubbed non-fatal message, bypassing only the Debug gate) and "Crash
now" (a real `fatalError`, so the next launch sends a real crash), plus a read-only block:
analytics on/off, replay on/off, PostHog host, Sentry on/off, version/build, the hashed user id.
It works in Release too — hidden behind the taps, not a build flag.

## What Raj does in PostHog

- Turn on **"Discard client IP data"** in the project settings. PostHog otherwise adds a rough location from the IP on the server, and the app's manifest and label declare no Coarse Location.
- Create the project on the EU host and put the `phc_` key in `Secrets.xcconfig` (see `Secrets.xcconfig.example`). Session replay stays off in the project too.

## Protection

- **Project key (`phc_…`).** It ships in the app and is write-only. A leaked key can send fake events but cannot read data. Rotate it in project settings and ship an update.
- **Personal key (`phx_`).** Never in the app or in git.
- **No ATT.** No linking with third-party data for ads, and no data brokers.
- **Privacy manifest.** Update `PrivacyInfo.xcprivacy` to match the label above. `NSPrivacyTracking` stays false. Check whether the PostHog package ships its own manifest (**not verified**).
- **Erasure.**
  - Delete All Data and account delete call `reset()` on the device.
  - Deleting the person in PostHog needs the personal key. Do it from the sub-spec 4 Worker, or by hand on request. The endpoint is **not verified**.

## Files

- New `Spend/Services/Analytics.swift`.
- `Spend/App/SpendApp.swift`.
- `Spend/Views/Settings/PrivacySecuritySettingsView.swift`.
- `Spend/Views/DataControlsView.swift:21`: the in-app "No ads, no tracking" copy. Delete All calls `reset()`.
- `Spend/Views/Settings/HelpFeedbackSettingsView.swift`: the support email includes the hashed ID if the user agrees.
- `Spend/PrivacyInfo.xcprivacy`.
- `project.pbxproj`: the posthog-ios package.
- Docs (router): `docs/AppReviewNotes.md:63`, `docs/AppStoreChecklist.md`, `docs/GoogleVerification.md` (tell Google).

## Test plan

- Switch off → `track(.tabViewed(.home))`: the fake sink gets nothing, and `optOut` was called.
- Off, then on → the next event is sent; events from while it was off are not.
- `identityHash(provider: "apple", subject: "001.abc")` is stable, does not contain the subject, and differs for "google".
- Sign-in → `identify(hash)` once. Sign-out → `reset()`.
- `activation` fires once per install: never on DemoData, never on a test tap.
- Every event's keys are in an allowlist. No payload string equals a merchant or amount in the DemoData store.
- Autocapture audit: the captured properties of a tap on a Recent row (fake transport) contain no amount and no merchant. This test gates autocapture.
- Flag unknown or offline → the default screen.
- `ui-driver`: the switch at AX5, with a VoiceOver label; the setup privacy line.
- Device: events arrive from TestFlight; no replays recorded; the Xcode privacy report matches the label.

## Gate

- In-app copy and review notes are rewritten in the same release.
- Google is told first.
- The autocapture audit passes before autocapture is turned on.
- Lawyer view on EU consent before launch.

## Sources (read 25 Sep 2026)

- [PostHog iOS](https://posthog.com/docs/libraries/ios), [configuration](https://posthog.com/docs/libraries/ios/configuration), [usage](https://posthog.com/docs/libraries/ios/usage), [identify](https://posthog.com/docs/product-analytics/identify), [pricing](https://posthog.com/pricing), [key safety](https://posthog.com/questions/is-it-ok-to-expose-the-posthog-project-api-key-to-the-public)
- [Apple app privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Google user data policy](https://developers.google.com/terms/api-services-user-data-policy)
- The App Store pages are linked in the table.

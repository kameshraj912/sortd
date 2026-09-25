# Free-app overhaul: overview (25 Sep 2026, revised after Raj's review)

Status: **approved by Raj on 25 Sep, with the changes below.** Each sub-spec still passes its own gate.
Worktree: `/Users/kameshraj/Developer/Sortd/.claude/worktrees/idea-free-overhaul`. The paths read are listed at the end.

## Summary: what changes for a user

1. **Everything is free.** No Pro, no paywall, no locked tab. Settings › About has an optional "Leave a tip", which unlocks nothing.
2. **Setup takes one button.** You can tap Continue all the way through, because every step has a default. The first purchase that logs itself gets a small celebration.
3. **Tips explain the buttons.** Each short tip appears the first time a button matters, one tip at a time.
4. **Purchases back up to your own iCloud automatically**, and restore on a new phone. Signing in with Apple or Google is optional.
5. **The app feels more solid.** The same haptic for the same kind of action, transitions that follow where you are going, and instant results with undo.
6. **Usage and crash data are shared** with PostHog and Sentry, tied to your account ID as a one-way hash. You can turn this off in Settings.

## What does NOT change

- **No server of ours holds purchase data.** Purchases live on the phone, and the backup lives in the user's own iCloud.
  - The only exception is one stateless Cloudflare Worker. It revokes Apple tokens and deletes PostHog persons.
  - PostHog and Sentry receive usage and crash data. They never receive amounts, merchants, emails, card digits, notes or Gmail content.
- Every source still goes through `TransactionLogger.log(_:in:)`. Enums stay raw strings. Totals use `audValue`.
- System UI first: Liquid Glass, SF Symbols, Dynamic Type, and a VoiceOver label on every amount and chart.
- No bank logins, no scraping. Secrets stay in the Keychain or in the Worker's secret store. The age rating stays the same.
- Out of scope: the "leave alone" items in `docs/ux-research/07-app-references.md` (biometrics, app blocking, "pause before you buy", pricing tiers).

## Sub-specs in ship order

Sizes are rough guesses, **not verified**. "Label" means the App Privacy label changes.

| # | Sub-spec | Main files (checked) | Depends on | Size | Migration | Label | Flag | What the user sees after it |
|---|---|---|---|---|---|---|---|---|
| 1 | [free](2026-09-25-free-app-overhaul-1-free.md): remove Pro, add tip jar | delete `ProStore`, `CompedPro`, `PaywallView`, `SecretCodeSheet`; new `Services/TipJar.swift`, `Settings/TipJarView.swift`, `SortdTips.storekit`; 23 edits under `Spend/` | none | 2.5 d | no | no (a tip IAP is not a data type) | no | Nothing locked. "Leave a tip" in About. |
| 2 | [analytics](2026-09-25-free-app-overhaul-2-analytics.md): PostHog | new `Services/Analytics.swift`, `SpendApp.swift`, `PrivacySecuritySettingsView.swift`, `DataControlsView.swift`, `PrivacyInfo.xcprivacy` | 1 | 3 d | no | **yes: linked** | PostHog flags (A/B only) | A "Share usage and crash reports" switch. |
| 2b | [crash reports](2026-09-25-free-app-overhaul-2b-crash-reports.md): Sentry live | `Services/CrashReporting.swift`, `PrivacyInfo.xcprivacy`, `scripts/preflight.sh` | 1, 2 (same release) | 1 d | no | **yes: Crash Data, linked** | no | Nothing visible. |
| 3 | [iCloud backup](2026-09-25-free-app-overhaul-3-icloud-backup.md) | `Services/Backup.swift`, new `Services/CloudBackup.swift`, `Spend.entitlements`, `Settings/BackupDataSettingsView.swift` | 1; paid enrolment | 5 d | no | no (not verified) | no | "Backed up to iCloud 2 min ago." Restore on a new phone. |
| 4 | [sign-in](2026-09-25-free-app-overhaul-4-sign-in.md) | new `Services/AccountStore.swift`, `GoogleAuth.swift`, `Spend.entitlements`, new `Settings/AccountSettingsView.swift`; Worker | 2, 3 | 4 d + Worker | no | covered by 2 | no | Optional Apple or Google sign-in. |
| 5 | [motion](2026-09-25-free-app-overhaul-5-motion.md) | new `Components/Feedback.swift`, the 14 files that use `sensoryFeedback`, `HomeView.swift`, `ActivityView.swift` | 1 | 3 d | no | no | DEBUG `SPEND_ACTIVITY_DAYS` | Consistent haptics. Details zoom open from Home. |
| 6 | [onboarding](2026-09-25-free-app-overhaul-6-onboarding.md) | `SetupFlow.swift`, `OnboardingView.swift`, `SetupPages.swift`, `FinishSetupCard.swift`, new `Activation.swift` | 1, 2, 5 (the restore button needs 3) | 4 d | no | no | DEBUG `SPEND_NEW_SETUP`, then a PostHog A/B | Continue all the way. The aha celebration. |
| 7 | [tips](2026-09-25-free-app-overhaul-7-tips.md): TipKit | new `Components/Tips.swift`, `SpendApp.swift`, 5 screens | 6 | 2 d | no | no | no | One tip the first time you use +, swipe, Search, Insights. |
| 8 | [instant](2026-09-25-free-app-overhaul-8-instant.md) | `ActivityView.swift`, `PendingDeletes.swift`, `GmailViews.swift`, `AddTransactionView.swift`, `InsightsView.swift`, new `Suggestions.swift` | 5 | 4 d | no | no | no | Instant results with undo. Suggestions. A budget heads-up. |
| 9 | [brand](2026-09-25-free-app-overhaul-9-brand.md) | `Assets.xcassets`, `Brand/`, new `AppIcon.icon` | 1 | 3 d (mostly design) | no | no | no | A layered Liquid Glass icon. New store screenshots. |

**Later, no stub yet.** Each of these needs a new app target, so each gets its own spec:
- **Live Activities**: Gmail sync progress, and the monthly budget.
- **Share Extension**: share a receipt into Sortd.

## Order rationale

- **Free first.** Every later sub-spec would otherwise have to handle `isPro`. It also ends the `SORTD_BETA` problem.
- **No SwiftData migration.** The one option that needs a migration is live CloudKit sync (sub-spec 3, option B). It would drop `.unique` in a `SchemaV2`, and it would then ship alone, straight after 1.
- **Analytics and crash reports go out together**, before onboarding. The old setup needs a baseline, and the label changes only once.
- **Backup comes before sign-in.** Backup needs no account. Sign-in then adds identity.
- **Motion comes before onboarding and tips**, so both use the same haptic map.
- **Icons come last.**
- **Before sub-spec 1 starts:**
  - take `ui-driver` baseline screenshots;
  - record the `scripts/test.sh --known-bugs` count.

  Neither may get worse.
- **One sub-spec at a time, never in parallel.**
  - 1, 5, 6, 7 and 8 all edit `HomeView.swift`.
  - 1, 5 and 6 all edit `OnboardingView.swift`.

## Protection and compliance

| Risk | Measure | Sub-spec | Source (read 25 Sep 2026) |
|---|---|---|---|
| A bot runs up a bill | **Our only endpoint is the Worker.** It takes a signed-in hash or an Apple code, and has a per-IP rate limit and a tight budget. App Attest if abused. **iCloud:** the user's own quota pays for storage | 3, 4 | [App Attest](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity). Billing: forum sources only, **not verified** |
| API quotas | **Gmail:** 6,000 units per minute per user; back off on errors (`GmailSync`). **CloudKit:** honour `retryAfterSeconds`; show `quotaExceeded` as "iCloud is full" | 3 | [Gmail quota](https://developers.google.com/workspace/gmail/api/reference/quota), [CKError](https://developer.apple.com/documentation/cloudkit/ckerror/code/requestratelimited) |
| Leaked PostHog key | **The `phc_` key is write-only:** a leak allows fake events, and no reading. Rotate it and ship an update. **The personal `phx_` key** lives only in the Worker | 2 | [PostHog key](https://posthog.com/questions/is-it-ok-to-expose-the-posthog-project-api-key-to-the-public) |
| Leaked Sentry DSN | Junk events at worst. Rotate the client key | 2b | **not verified** |
| Amounts caught on screen | **Session replay is off.** Element autocapture stays off until an audit test shows no amounts or merchants are captured. Sensitive views get `ph-no-capture` | 2 | [PostHog config](https://posthog.com/docs/libraries/ios/configuration) |
| Personal data in crash reports | `sendDefaultPii` false, so no IP is sent. Screenshots, view hierarchy, breadcrumbs and replay are off. **Scrub exception values and messages.** The user is set as the hash only | 2b | [Sentry options](https://docs.sentry.io/platforms/apple/configuration/options/), [data collected](https://docs.sentry.io/platforms/apple/data-management/data-collected/) |
| Label and manifest | **Linked:** Product Interaction, User ID, Device ID, and Crash, Performance and Other Diagnostic Data. **Not tracking.** No ATT prompt. Update `PrivacyInfo.xcprivacy`. This matches the norm among 7 comparable apps (table in 2) | 2, 2b | [App privacy details](https://developer.apple.com/app-store/app-privacy-details/), [Sentry manifest](https://docs.sentry.io/platforms/apple/data-management/apple-privacy-manifest/) |
| 3.1.1 tips | Tips are consumable IAPs that unlock nothing | 1 | [Guidelines](https://developer.apple.com/app-store/review/guidelines/) |
| 4.8 and 5.1.1(v) | **Apple sign-in is offered beside Google.** Account deletion is in the app and wipes the tokens, the PostHog person and, if the user chooses, their purchases | 4 | [Guidelines](https://developer.apple.com/app-store/review/guidelines/), [account deletion](https://developer.apple.com/support/offering-account-deletion-in-your-app/) |
| Gmail Limited Use and CASA | **No Gmail content or counts go to PostHog or Sentry.** Nothing from Gmail goes on a server we run, which is the basis of the CASA exemption request (`docs/GoogleVerification.md:28`). The retired roadmap estimated CASA at US$675–855 a year | 2, 2b, 3 | [Google user data policy](https://developers.google.com/terms/api-services-user-data-policy) |
| AU Privacy Act, SG PDPA, GDPR | **Export:** exists. **Delete:** Delete All Data, extended to iCloud and to the PostHog and Sentry identity. **Consent record:** kept on the device. **For a lawyer:** EU opt-in, and who the policy names | 2, 3, 4 | not verified |
| Backup file security | Encrypted on the device. The key is kept in iCloud Keychain. A recovery key is optional | 3 | **not verified** |

## Decisions (25 Sep 2026)

**Decided by Raj:**
1. **Tip jar:** yes, three consumables.
2. **Sentry:** keep it, and run it live.
3. **Analytics:** PostHog, tied to the user. Session replay off. Feature flags on.
4. **Consent:** on by default, with a switch.

**Your defaults, which Raj accepted:**
- Raj authorises the `SORTD_BETA` removal (`SORTD_GMAIL` stays).
- Backup goes to iCloud first.
- Sign-in uses the revoke Worker.
- "Oriented" means motion follows direction.
- The day list goes behind a flag.
- The mascot comes later.

**Still open (default if Raj says nothing):**
1. **PostHog region.** Default: EU.
2. **Person profiles before sign-in.** Default: `.always`. The cost is not verified.
3. **Crash Data linked or not linked.** Default: linked (`setUser`), as Raj asked. Most spending trackers in the table keep it "not linked".
4. **Tip prices.** Raj sets them in App Store Connect. Default: three tiers.
5. **Lawyer:** EU consent, and the name in the privacy policy.

## Risks

- **The privacy story changes.** "Data Not Collected" becomes "linked to you". Sortd still does no tracking in Apple's sense.
  - Rewrite the in-app copy (`DataControlsView.swift:21`), `docs/AppReviewNotes.md:63` and `docs/AppStoreChecklist.md` in the same release.
  - Tell Google before the policy changes, while the restricted-scope review is open.
- **Site copy is being redone separately.** Its privacy page must match the label before the App Store submission.
- **Autocapture could leak amounts** through VoiceOver labels (`Money.spoken`). It stays off until the audit test passes.
- **Crash messages could carry merchant text.** Scrubbing is in 2b's tests.
- **Work is thrown away:** PR #20's AX5 paywall fixes, `paywall-steps`, and Redeem Code (PR #15).
- **Gmail could vanish from Release** if `SORTD_GMAIL` is removed along with `SORTD_BETA` (`Features.swift:9`). A test checks this.
- **Paid enrolment blocks 3, 4 and the tip products.**
- **A rule gap:** `Backup.restore` inserts rows directly (`Backup.swift:379`), but `CLAUDE.md` names only `DemoData` as allowed to. Record the exception.

## Sources and paths read

**Repo (this worktree):**
- Top level: `CLAUDE.md`, `HANDOVER.md`.
- `docs/`: `AgentPipeline.md`, `AppStoreChecklist.md`, `AppReviewNotes.md`, `GoogleVerification.md`, `ux-research/01`, `02`, `03` and `07`.
- `Brand/README.md`.
- Code:
  - `Spend/Services/`: `ProStore.swift`, `SetupFlow.swift`, `CrashReporting.swift`, `GoogleAuth.swift`, `SpendStore.swift`, `Backup.swift`.
  - `Spend/App/`: `SpendApp.swift`, `Features.swift`.
  - `Spend/Views/`: `OnboardingView.swift`, `Onboarding/SetupPages.swift`, `Components/Theme.swift`.
  - `Spend/PrivacyInfo.xcprivacy`, the `AppIcon` `Contents.json`, and the pbxproj build settings.
- Greps:
  - `isPro|ProStore|PaywallView|ProPaywall`: 38 files.
  - `sensoryFeedback`: 20 hits in 14 files.

**Retired roadmap:** read from the checked-out copy at `/Users/kameshraj/Developer/Sortd/.claude/worktrees/beta-rc1/docs/Roadmap.md`. I had no shell to run `git show`.

**Correction to the brief:** the app does not link the GoogleSignIn SDK. `GoogleAuth.swift` runs its own OAuth and already receives a Google ID token.

**Web sources:** listed in each stub, all read on 25 Sep 2026.

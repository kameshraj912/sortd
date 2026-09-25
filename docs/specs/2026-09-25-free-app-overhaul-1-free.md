# Overhaul 1: the whole app is free, with a tip jar (25 Sep 2026)

Part of `2026-09-25-free-app-overhaul-overview.md`. Worktree `idea-free-overhaul`.
**Raj decided on 25 Sep:** keep StoreKit for a tip jar only.

## Problem

Raj: "I am removing the paid one; the whole app is free now."

Today Pro locks:
- Gmail and the receipt camera
- the Insights tab
- Subscriptions & bills, and bill reminders
- category budgets

Removing Pro touches 27 files under `Spend/`, 5 test files, 5 scripts and CI. `SORTD_BETA` in Release (`project.pbxproj:422`) has to go before any App Store build anyway (`CLAUDE.md`). Raj wants a tip jar in place of Pro: three tips, and nothing unlocked by any of them.

## Options

| | A. Delete Pro, add a small `TipJar` (decided) | B. Keep `ProStore`; `isPro` always true | C. Delete all StoreKit code |
|---|---|---|---|
| Work | 2.5 d | 0.5 d | 2 d |
| Risk | wide diff; the `SORTD_BETA` edit needs Raj | dead entitlement code; unused subscription config | no tip jar, which Raj wants |
| Gives up | PR #20's AX5 paywall fixes, Redeem Code (PR #15), branch `paywall-steps` | clarity | tips |

## Recommendation

A, in one PR, so no half-free build ships.

**`TipJar`** (`@Observable`, about 60 lines):
- Loads 3 consumables and buys one.
- Finishes every verified transaction from `Transaction.updates` and `Transaction.unfinished`.
- Stores nothing: no entitlements, no `currentEntitlements`, no restore.

**Settings › About:**
- A "Leave a tip" row opens a sheet with three buttons, each showing the App Store's `displayPrice`.
- After a tip: a plain "Thank you." Nothing changes in the app.
- Keep `AppStore.requestReview` if it is used.

**Order:** `SetupFlow` and its tests first (pure logic), then `TipJar`, then the views.

**App Store setup (Raj, in App Store Connect):**
- Create three consumable IAPs: `com.kameshraj.spend.tip.small`, `.medium`, `.large`. These IDs are a proposal. Raj sets the prices; I have not invented any.
- Each needs a review screenshot of the tip sheet. Attach all three to the version.
- Retire the three Pro products. They were never approved (`AppStoreChecklist.md` lists them as "to create").
- Review note: "Tips are consumable IAPs. They unlock nothing. Every feature is free."

**Guideline 3.1.1** says: "Apps may use in-app purchase currencies to enable customers to 'tip' the developer or digital content providers in the app." ([guidelines](https://developer.apple.com/app-store/review/guidelines/), read 25 Sep 2026.) That sentence sits beside "in-game currencies". Reading it as covering a plain tip IAP is my interpretation, **not verified** with App Review.

## Files

**Delete:**
- `Spend/Services/ProStore.swift` (also holds `BetaAccess`)
- `Spend/Services/CompedPro.swift`
- `Spend/Views/PaywallView.swift` (also holds `ProGate`, `ProLockedView`, `redeemOfferCode`)
- `Spend/Views/SecretCodeSheet.swift`
- `SpendTests/ProStoreTests.swift`, `SpendTests/BetaAccessTests.swift`, `SpendTests/CompedProTests.swift`

**Replace:** `Spend/SortdPro.storekit` → `Spend/SortdTips.storekit` (3 consumables only).

**New:**
- `Spend/Services/TipJar.swift`
- `Spend/Views/Settings/TipJarView.swift`
- `SpendTests/TipJarTests.swift`: StoreKit Testing, needs the iOS 27 simulator (as `ProStoreTests` did)

**Edit, app:**
- `Spend/App/SpendApp.swift`: 3× `ProGate`; replace `launch.proRefresh` (:292) with the TipJar start-up.
- `Spend/App/Features.swift`: drop `SORTD_BETA` from the condition. **Keep `SORTD_GMAIL`.**
- `Spend/App/DebugScreens.swift`: the paywall screen becomes the tip screen.
- `Spend/Services/SetupFlow.swift`: remove `isPro` and `.pro`. `.email` depends on `gmailFeature && wantsGmail`.
- `Spend/Services/SetupProfile.swift`: remove `proOrder`; simplify `applyPendingBillReminders`.
- `Spend/Services/Reminders.swift:77,105`, `Spend/Services/GmailSync.swift:203`.
- `Spend/Services/CrashReporting.swift`: belongs to sub-spec 2b. Here, only keep it compiling.
- `Spend/Intents/SpendQuestionIntents.swift:124`.
- `Spend/Views/OnboardingView.swift`: Pro page, trial, redeem, every `pro.isPro`.
- `Spend/Views/Onboarding/SetupPages.swift:218,236`.
- `Spend/Views/SettingsView.swift`: Pro row :25–40, sheet :108, `ProGate` :97.
- `Spend/Views/Settings/AboutSettingsView.swift`: remove the `CompedPro` line (:29), add the tip row.
- `Spend/Views/Settings/BillsRemindersSettingsView.swift`, `DataControlsView.swift:104`.
- `Spend/Views/HomeView.swift:283`, `Home/FinishSetupCard.swift`, `InsightsView.swift:213`, `AddTransactionView.swift:227`, `GmailViews.swift:58`, `RecurringView.swift:259`, `Components/RefreshNote.swift:23`.

**Edit, project (needs Raj):**
- `Spend.xcodeproj/project.pbxproj`: `SORTD_BETA` at :422.
- `Spend.xcodeproj/xcshareddata/xcschemes/Spend.xcscheme:70`: point it at `SortdTips.storekit`.

**Edit, tests, scripts, CI:**
- `SpendTests/SetupFlowTests.swift`, `SpendTests/SetupProfileTests.swift`.
- `scripts/test.sh`: `--storekit` now runs `TipJarTests`. The same change in `scripts/check.sh` and `scripts/common.sh:24`.
- `scripts/preflight.sh:26–41`: the `SORTD_BETA` check becomes "must be absent". The Sentry check changes in 2b.
- Flag lists in `scripts/hooks/pre-commit:42` and `scripts/preflight.sh:101`: drop `SPEND_PRO`, `SPEND_PAYWALL_DEMO`, `SPEND_BETA`.
- `.github/workflows/swift.yml:46`: skip `TipJarTests` instead of `ProStoreTests`.

**Docs (router or release-manager, not the builder):**
- `CLAUDE.md`: "Paid features" becomes "Tip jar".
- `HANDOVER.md`.
- `docs/AppStoreChecklist.md`: drop grace period and retention messaging; keep the Small Business Program.
- `docs/AppReviewNotes.md`, `docs/AppStoreListing.md`.

## Test plan

Behaviours for `test-writer`:
- `SetupFlow(goals: [.receipts], gmailFeature: true)`: `path` contains `.email`.
- Any `SetupFlow`: no Pro step. `SetupFlow(gmailFeature: false)`: no `.email`.
- Bill reminders on: scheduling is not skipped. Extract a pure `Reminders.shouldSchedule(enabled:)`.
- Category-limit check with limits set: returns over-limit lines, with no Pro condition.
- Upcoming-bills intent: returns the bills answer, never "part of Sortd Pro".
- `applyPendingBillReminders` with the bills intent set: turns reminders on.
- **TipJar** (StoreKit Testing):
  - `load()` returns exactly the 3 tip IDs, sorted by price.
  - Buying `tip.small` → `.thanked`, and the transaction is finished.
  - Cancelling → `.cancelled`, and no thank-you shows.
  - Buying twice works (consumable).
  - `TipJar` exposes no Boolean for the rest of the app to read.
- Launch with the old keys (`proStoreEnvironment=production`, a comped code): no crash and no Pro text (UI check).
- Script check: `grep -rE 'isPro|ProStore|PaywallView|ProGate|SORTD_BETA|CompedPro|currentEntitlements' Spend/` finds nothing.
- Release build: `Features.gmail == true`.

`ui-driver`:
- Insights opens. No Pro row in Settings, no Pro page in setup.
- Settings › About › Leave a tip: three prices and a thank-you, at AX5 and on SE.
- Scan Receipt opens the scanner. The bills switch asks for notification permission.

Real device (TestFlight sandbox): one tip purchase, and the thank-you.

## Gate

- Raj allows the `SORTD_BETA` edit.
- The three tip products exist in App Store Connect before the store build.
- `scripts/test.sh` and `--storekit` are green.
- The known-bug count does not rise.
- CI is green.

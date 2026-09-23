# Sortd — iPhone spending tracker (repo: `~/Developer/Sortd`, out of iCloud on purpose)

Logs Apple Pay taps, reads receipts from Gmail and the camera, and shows where the
money goes. Multi-currency (AUD, SGD and others) with on-device FX. No server: everything
stays on the phone.

**Status (20 Sep 2026):** heading for TestFlight. Paid Apple Developer enrolment is the
open blocker — nothing can be uploaded until it clears. Site is live at sortd.page.
Google OAuth restricted-scope review submitted 20 Sep 2026.

- Store readiness: `docs/AppStoreChecklist.md` (read the top section before any App Store build)
- Listing copy: `docs/AppStoreListing.md` · Review notes: `docs/AppReviewNotes.md`
- Google: `docs/GoogleVerification.md` · Brand and trademark: `Brand/README.md`
- Before any upload: `scripts/preflight.sh` (add `--appstore` for a store build)

## Several Claude sessions at once — read before editing

Raj often runs several Claude sessions (and forks) on Sortd at the same time. They share
this folder, git, the simulator and the live website. Follow this order every time.

**1. Start: get your own copy.** One task = one git worktree + one branch.
- Check first: `git status`. If it shows changes you didn't make, another session is working here.
- Make your copy: `git worktree add .claude/worktrees/<task> -b <task> main`, then work only
  inside `~/Developer/Sortd/.claude/worktrees/<task>`. (In the Claude app, "start in a worktree" does the same.)
- The main `~/Developer/Sortd` folder is for Raj and for merging. Don't do task work there
  while another session is active.

**2. Test on your own simulator.**
- Each worktree already gets its own build folder. Also use your own simulator:
  `xcrun simctl clone "iPhone 18 Pro" "Sortd-<task>"`, then test with `name=Sortd-<task>`.
- "Invalid device state" or "server died" means another session is using that simulator.
  That's not a code failure. Switch simulator and run again.

**3. Commit only your own work.**
- Stage files by name: `git add <file> <file>`. Never `git add -A`, `git add .` or `git commit -a`.
- If a file has your change mixed with another session's, don't commit their part. Tell Raj.
- After committing, run `git show --stat HEAD` and check that every file listed is yours.
- Commit and push only when Raj asks.

**4. Push safely.**
- `git pull --rebase origin <branch>` first, then `git push`. Never force-push a shared branch.
- Run the full test suite on a clean copy of what you're pushing, not a folder with other
  sessions' uncommitted edits.

**5. Deploy the website from one place only.**
- `npx wrangler deploy` uploads the files on disk, **including other sessions' uncommitted
  edits**. Deploy only when `git status site/` is clean and matches the pushed branch.
- One session deploys at a time.

**6. Finish.**
- When Raj says merge: merge the branch into `main` from the main folder with tests
  passing, then `git worktree remove .claude/worktrees/<task>` and delete the branch.
- Don't leave background jobs running (no "wait until a file exists" loops). Stop anything
  you started before you finish.

## Build / test
- Open: `open Sortd.xcodeproj` (Xcode 27, iOS 26+ target, SwiftUI + SwiftData + Swift Charts + App Intents).
- Build: `xcodebuild -project Sortd.xcodeproj -scheme Sortd -destination 'generic/platform=iOS Simulator' build`
- Test: `xcodebuild -project Sortd.xcodeproj -scheme Sortd -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test` (Swift Testing, in-memory store).
- Sample data in the simulator: launch with env `SORTD_DEMO=1` (DEBUG only), or tap "Explore with sample data" on the first screen.
- On the phone: Xcode → Signing & Capabilities → pick Raj's team. Free team = re-install every 7 days.

## Paid features
Pro gates Gmail, the receipt camera, Insights, Subscriptions & bills, and category budgets.
Everything else is free forever. Entitlements come from StoreKit 2 on the device.

`SORTD_BETA` is set on the **Release** config so TestFlight testers get Pro without paying
(`ProStore.isPro`). **It must come out before the App Store build** — it also unlocks Pro
for App Review, who would then never see the paywall. `scripts/preflight.sh --appstore`
fails while it is still there.

## Layout
- `Sortd/App` — app entry, tabs, DEBUG sample data.
- `Sortd/Models` — SwiftData models (`Transaction`, `MerchantRule`, `FXRate`), enums (`Card`, `SpendCategory`, `TxnSource`), bank presets.
- `Sortd/Services` — parsing, categorising, de-duplication, FX, Gmail, receipts, Pro, app lock.
- `Sortd/Intents` — `LogPurchaseIntent`, `LogWalletTapIntent`, and the Siri question intents.
- `Sortd/Views` — SwiftUI screens; `Views/Components` holds shared rows and badges.
- `SortdTests` — unit tests for the pure logic and the StoreKit flows.

## Rules for this codebase
- Every source goes through `TransactionLogger.log(_:in:)`. It categorises and de-duplicates. Never insert a `Transaction` directly (only `DemoData` does).
- Enums are stored as raw strings (`cardRaw`, `categoryRaw`, `sourceRaw`) so SwiftData predicates work.
- Totals use `audValue` (AUD). Keep the original amount and currency too.
- UI uses system components first (Apple HIG, Liquid Glass): SF Symbols, `.monospacedDigit()` on money, Dynamic Type, a VoiceOver label on every amount and chart.
- No bank passwords, no screen scraping. Secrets (the Google refresh token) go in the Keychain, never in git.
- Debug-only escapes (`SORTD_DEMO`, `SORTD_PRO`, `SORTD_PAYWALL_DEMO`, `SORTD_REEL_TAP`) stay inside `#if DEBUG`.
- The project uses folder-synced groups: new files under `Sortd/` are picked up with no pbxproj edits.

## Known gaps
- **No backup.** SwiftData is local-only — losing the phone loses every transaction. CloudKit private database is the fix and is not built yet.
- Refunds and reversals never come back, so tap-logged totals drift up over time.
- Cash and non-Apple-Pay spend is invisible unless entered by hand.

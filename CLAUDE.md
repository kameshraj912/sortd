# Sortd — iPhone spending tracker (repo folder is `Spend`)

Logs Apple Pay taps, reads receipts from Gmail and the camera, and shows where the
money goes. Multi-currency (AUD, SGD and others) with on-device FX. No server: everything
stays on the phone.

**Status (20 Sep 2026):** heading for TestFlight. Paid Apple Developer enrolment is the
open blocker — nothing can be uploaded until it clears. Site is live at sortd.page.
Google OAuth restricted-scope review submitted 20 Sep 2026. The app is free since 25 Sep 2026.

- Store readiness: `docs/AppStoreChecklist.md` (read the top section before any App Store build)
- Listing copy: `docs/AppStoreListing.md` · Review notes: `docs/AppReviewNotes.md`
- Google: `docs/GoogleVerification.md` · Brand and trademark: `Brand/README.md`
- Before any upload: `scripts/preflight.sh` (add `--appstore` for a store build)

## Several Claude sessions at once — read before editing

Raj often runs several Claude sessions (and forks) on Sortd at the same time. They share
this folder, git, the simulators and the live website. The rules are enforced by scripts in
`scripts/`; use them instead of typing git, xcodebuild or simctl by hand.
Full design: `docs/AgentPipeline.md`.

**1. Start: get your own copy.** One task = one worktree + one branch + one simulator.
- Check first: `git status`. Changes you didn't make mean another session is working here.
- `scripts/worktree-new.sh <task>` makes `.claude/worktrees/<task>` on branch `<task>` from
  `main`, installs the git hooks, and clones simulator `Sortd-<task>`. Work only inside it.
- The main folder `~/Developer/Sortd` is for Raj and for merging. No task work there.

**2. Build and test with the scripts.**
- `scripts/build.sh` compiles. `scripts/test.sh` runs the suite on this worktree's simulator
  (`--known-bugs` also runs the tests tagged as known bugs, `--storekit` adds ProStoreTests,
  `--only Suite` runs one suite). Logs land in `.build/`.
- "Invalid device state" or "server died" means two sessions share a simulator. Use your own.

**3. Commit only your own work.**
- Stage files by name: `git add <file> <file>`. Never `git add -A`, `git add .` or `git commit -a`.
- The pre-commit hook blocks secrets, files over 50 MB, debug flags outside `#if DEBUG`, and
  Swift that does not parse. Fix the cause; do not bypass it.
- If a file mixes your change with another session's, commit only your part or tell Raj.
- After committing, `git show --stat HEAD` and check every file listed is yours.
- Commit and push only when Raj asks.

**4. Push through a pull request.**
- `git pull --rebase origin <branch>` first, then `git push -u origin <branch>`, then
  `gh pr create --base main`. The pre-push hook refuses direct pushes to `main`.
- Merge only when CI is green and Raj says so: `gh pr merge <n> --merge --delete-branch`.
- Never force-push a shared branch. Never rewrite pushed history; fix with a new commit.

**5. Deploy the website from one place only.**
- `npx wrangler deploy` uploads the files on disk, **including other sessions' uncommitted
  edits**. Deploy only when `git status site/` is clean and matches the pushed branch.
- One session deploys at a time.
- The account Worker deploys from `worker/` (`cd worker && npx wrangler deploy`), separately from the site. See `worker/README.md`.

**6. Finish.**
- `scripts/worktree-done.sh <task>` removes the worktree, its simulator and its build folder,
  and deletes the branch once `main` has it. It refuses while there is uncommitted work.
- `scripts/worktree-audit.sh` shows what every worktree still holds. `scripts/clean.sh --yes`
  frees disk (each build folder is ~3.5 GB).
- Don't leave background jobs running. Stop anything you started before you finish.

## Build / test
- Open: `open Spend.xcodeproj` (Xcode 27, iOS 26+ target, SwiftUI + SwiftData + Swift Charts + App Intents).
- Build: `scripts/build.sh`. Test: `scripts/test.sh` (Swift Testing, in-memory store, on an iOS 27
  simulator: StoreKit tests fail on iOS 26.x simulators, see HANDOVER.md).
- CI (`.github/workflows/swift.yml`) builds and tests on a pinned Xcode. Code must compile on
  that Xcode too: an SDK-only symbol needs `#if compiler(>=...)`, not just `#available`.
- Sample data in the simulator: launch with env `SPEND_DEMO=1` (DEBUG only), or tap "Explore with sample data" on the first screen.
- On the phone: Xcode → Signing & Capabilities → pick Raj's team. Free team = re-install every 7 days.

## Tip jar
Everything is free forever: Gmail, the receipt camera, Insights, Subscriptions & bills,
and category budgets included. Settings › About has a "Leave a tip" row: three
consumable tips that unlock nothing. StoreKit 2 stays in the app only for that.

`SORTD_BETA` is gone.

## Layout
- `Spend/App` — app entry, tabs, DEBUG sample data.
- `Spend/Models` — SwiftData models (`Transaction`, `MerchantRule`, `FXRate`), enums (`Card`, `SpendCategory`, `TxnSource`), bank presets.
- `Spend/Services` — parsing, categorising, de-duplication, FX, Gmail, receipts, Pro, app lock.
- `Spend/Intents` — `LogPurchaseIntent`, `LogWalletTapIntent`, and the Siri question intents.
- `Spend/Views` — SwiftUI screens; `Views/Components` holds shared rows and badges.
- `SpendTests` — unit tests for the pure logic and the StoreKit flows.

## Rules for this codebase
- Every source goes through `TransactionLogger.log(_:in:)`. It categorises and de-duplicates. Never insert a `Transaction` directly (only `DemoData` and `Backup.restore` do; restore puts back rows the logger already checked).
- Enums are stored as raw strings (`cardRaw`, `categoryRaw`, `sourceRaw`) so SwiftData predicates work.
- Totals use `audValue` (AUD). Keep the original amount and currency too.
- UI uses system components first (Apple HIG, Liquid Glass): SF Symbols, `.monospacedDigit()` on money, Dynamic Type, a VoiceOver label on every amount and chart.
- No bank passwords, no screen scraping. Secrets (the Google refresh token) go in the Keychain, never in git.
- Debug-only escapes (`SPEND_DEMO`, `SPEND_REEL_TAP`) stay inside `#if DEBUG`.
- The project uses folder-synced groups: new files under `Spend/` are picked up with no pbxproj edits.

## Known gaps
- **No backup.** SwiftData is local-only — losing the phone loses every transaction. CloudKit private database is the fix and is not built yet.
- Refunds and reversals never come back, so tap-logged totals drift up over time.
- Cash and non-Apple-Pay spend is invisible unless entered by hand.

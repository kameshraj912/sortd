# Sortd — iPhone spending tracker (repo folder is `Spend`)

Logs Apple Pay taps, reads receipts with the camera, imports statements, and shows where the
money goes. Multi-currency (AUD, SGD and others) with on-device FX. Purchases stay on the
phone. What leaves it: opt-out usage counts and crash reports (off by default in the EU/UK),
the optional iCloud copy, and the account Worker (`worker/`) that only deletes accounts.

**Status (4 Oct 2026):** the TestFlight build is 1.0 (2) (build 1 was refused at processing: an App
Intent description said "Apple Pay", ITMS-90626); the App Store Connect record is
"Sortd: Spending Tracker" (bundle ID `com.kameshraj.sortd`, SKU `sortd-ios`). The account Worker is live
at `account.sortd.page`. The paid Apple Developer account is active
(team 7CLGYQ9P3L) with iCloud, Sign in with Apple and App Attest on the App ID. Site is live at sortd.page.
The app is free since 25 Sep 2026. Gmail receipts were removed on 2 Oct 2026 (Google wants a paid yearly
security assessment for the Gmail scope); "Continue with Google" stays as an optional sign-in.

- Store readiness: `docs/AppStoreChecklist.md` (read the top section before any App Store build)
- Listing copy: `docs/AppStoreListing.md` · Review notes: `docs/AppReviewNotes.md`
- Google (withdrawn): `docs/GoogleVerification.md` · Brand and trademark: `Brand/README.md`
- Before any upload: `scripts/preflight.sh` (add `--appstore` for a store build), then `scripts/check-archive.sh <archive>` on the archive

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
- The launch (hype) site soon.sortd.page deploys from `launch/` (`cd launch && npx wrangler deploy`). Its form posts to sortd.page/api/beta, so deploy `site/` first. See `launch/README.md`.

**6. Finish, and clean up at once.** Every task costs about 11.5 GB while it exists
(4.5 GB build folder + 7 GB simulator). Twenty left behind filled the disk on 2 Oct 2026
(275 GB of simulators, 2.4 GB free). Cleanup is the last step of every task and every
session, not optional.
- The moment a branch is merged, run `scripts/worktree-done.sh <task>`: it removes the
  worktree, its simulator and its build folder, and deletes the merged branch. Do it before
  starting the next task, not at the end of the day. It refuses while there is uncommitted
  work: commit, or move stray files out, then run it.
- A branch still waiting on a PR, or a task Raj pauses: `scripts/worktree-park.sh <task>`.
  It frees the simulator and build folder and keeps the worktree, branch and edits;
  `test.sh` and `build.sh` make both again on demand.
- A test or research worktree (bug hunt, UI pass, audit) goes as soon as its findings are
  copied out. Anything worth keeping is committed on a branch or saved under `docs/` first.
- Delete any extra simulator you made (`SORTD_SIM=<name> scripts/sim.sh delete`). Never
  leave a simulator behind that no live task uses.
- At most 4 task worktrees exist at once, and at most 2 builds run at once.
  `scripts/worktree-new.sh` refuses past the limit or when under 40 GB is free.
- Before ending a session: `scripts/worktree-audit.sh`, finish or park every task, then
  `scripts/clean.sh --yes` (build folders and simulators with no worktree), and say how much
  disk is free. A task that must stay open is named in the hand-off, with why.
- Don't leave background jobs running. Stop anything you started before you finish.

## Build / test
- Open: `open Spend.xcodeproj` (Xcode 27, iOS 26+ target, SwiftUI + SwiftData + Swift Charts + App Intents).
- Build: `scripts/build.sh`. Test: `scripts/test.sh` (Swift Testing, in-memory store, on an iOS 27
  simulator: StoreKit tests fail on iOS 26.x simulators, see HANDOVER.md).
- CI (`.github/workflows/swift.yml`) builds and tests on a pinned Xcode. Code must compile on
  that Xcode too: an SDK-only symbol needs `#if compiler(>=...)`, not just `#available`.
- Sample data in the simulator: launch with env `SPEND_DEMO=1` (DEBUG only), or tap "Explore with sample data" on the first screen.
- On the phone: `scripts/device.sh` (Developer Mode on, phone unlocked). Both configs sign with
  `Spend.entitlements` (iCloud, Sign in with Apple, App Attest, app groups); Xcode needs Raj's Apple ID
  in Settings › Accounts to refresh the profile. `SORTD_SIGNIN` and `SORTD_ICLOUD` are on in both configs.

## Tip jar
Everything is free forever: the receipt camera, Insights, Subscriptions & bills,
and category budgets included. Settings › About shows a "Leave a tip" row only once the three
consumable tips exist in App Store Connect (`TipJar` loads them; empty means no row). StoreKit 2
stays in the app only for that.

`SORTD_BETA` is gone.

## Layout
- `Spend/App` — app entry, tabs, DEBUG sample data.
- `Spend/Models` — SwiftData models (`Transaction`, `MerchantRule`, `FXRate`), enums (`Card`, `SpendCategory`, `TxnSource`), bank presets.
- `Spend/Services` — parsing, categorising, de-duplication, FX, receipts, Pro, app lock.
- `Spend/Intents` — `LogPurchaseIntent`, `LogWalletTapIntent`, and the Siri question intents.
- `Spend/Views` — SwiftUI screens; `Views/Components` holds shared rows and badges.
- `SpendTests` — unit tests for the pure logic and the StoreKit flows.

## Rules for this codebase
- Every source goes through `TransactionLogger.log(_:in:)`. It categorises and de-duplicates. Never insert a `Transaction` directly (only `DemoData` and `Backup.restore` do; restore puts back rows the logger already checked).
- The SwiftData store stays `cloudKitDatabase: .none`. With the iCloud entitlement, the default would mirror the store to CloudKit and crash at launch on the unique keys. Backup is `CloudBackup`'s own record.
- The bundle ID is `com.kameshraj.sortd` (widget `.widget`, tips `.tip.small/.medium/.large`), renamed from `…spend` on 4 Oct 2026 before the App Store record existed. The iCloud container (`iCloud.com.kameshraj.spend`), app group (`group.com.kameshraj.spend`), Keychain services and the backup file type (`com.kameshraj.spend.backup`) keep the old name on purpose: users never see them and CloudKit Production is already deployed there. Don't "fix" them.
- App Intent text (titles, descriptions, parameter text, Siri phrases) never says "Apple", so no "Apple Pay" there: write "Wallet" or "tap to pay". App Store Connect refuses the binary at processing (ITMS-90626; build 1.0 (1), 4 Oct 2026). `scripts/preflight.sh` checks the source and `scripts/check-archive.sh <archive>` checks the built metadata; run both before any upload.
- Enums are stored as raw strings (`cardRaw`, `categoryRaw`, `sourceRaw`) so SwiftData predicates work.
- Totals use `audValue` (AUD). Keep the original amount and currency too.
- UI uses system components first (Apple HIG, Liquid Glass): SF Symbols, `.monospacedDigit()` on money, Dynamic Type, a VoiceOver label on every amount and chart.
- No bank passwords, no screen scraping. Secrets (the account's Google sign-in token) go in the Keychain, never in git.
- Debug-only escapes (`SPEND_DEMO`, `SPEND_REEL_TAP`, `SPEND_OLD_SETUP` for the old setup flow, `SPEND_ACTIVITY_PAGER` for the old one-day-per-page Activity, `SPEND_FOUNDER_NOTE` for the founder's note, `SPEND_TAP_TEXT`/`SPEND_TAP_MERCHANT`/`SPEND_TAP_AMOUNT`/`SPEND_TAP_CARD`/`SPEND_TAP_DELAY`/`SPEND_TAP_REPEAT`/`SPEND_TAP_GAP` for the Apple Pay tap-replay hook, `SPEND_TAP_NTITLE`/`SPEND_TAP_NSUBTITLE`/`SPEND_TAP_NBODY` to replay Wallet's notification through the same hook, `SPEND_STORE_FAIL` to force the store-recovery screen) stay inside `#if DEBUG`.
- The project uses folder-synced groups: new files under `Spend/` are picked up with no pbxproj edits.

## Known gaps
- **Backup is one encrypted record** in the user's private iCloud (`CloudBackup`, on since 26 Sep 2026). Restore needs the same iCloud Keychain; there is no other copy.
- Refunds and reversals never come back, so tap-logged totals drift up over time.
- Cash and non-Apple-Pay spend is invisible unless entered by hand.

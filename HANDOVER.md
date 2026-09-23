# Sortd — handover (24 Sep 2026)

Read this first, then `CLAUDE.md`. Written by the "Sortd agent graph and pipeline" session.
Everything below was checked with commands on 24 Sep 2026, not taken from memory.

## 1. Where everything lives now

- **Repo:** `~/Developer/Sortd` (moved out of iCloud on purpose — iCloud "Optimize Mac Storage"
  was evicting `.git` files, which made git hang and time out). Never put the repo back in `~/Documents`.
- **Worktrees:** `~/Developer/Sortd/.claude/worktrees/<branch>` (gitignored on `rename-sortd`).
- **Media:** `~/Developer/Sortd/media/` — reels, ads, launch pack, profile images (moved from
  `~/Downloads/sortd-*`). Ignored via `.git/info/exclude`, not in git.
- **GitHub:** `kameshraj912/sortd` (private). On GitHub: `main`, `beta-prep`, `ux-refresh`,
  `abuse-findings`, `rename-sortd`. **Most branches exist only on this Mac** — push them before any risky change.
- **Main folder checkout:** `main` = `origin/main` (`71b07f7`). Untracked there, carried from the old
  folder: `claude-project/reels/out/ad06.mp4`, `docs/YC-W27-application.md`, `docs/drafts/`.

### Move check (done)
- `git fsck` clean. All 23 local branches copied; every branch tip matches the old repo except
  `main` (now = GitHub, old tip is contained in it) and `rename-sortd` (deliberately rebuilt).
- Every uncommitted file in every old worktree was carried over and compared byte for byte:
  1,213 files, 0 differences. Build caches (`.build-dd`, `build/dd`) were skipped on purpose.

### Old copies — safe to delete once Raj has looked
- `~/Documents/Spend`, `Spend-beta-rc1`, `Spend-copy`, `Spend-launch`, `Spend-paywall`,
  `Spend-refresh`, `Spend-speed`, `Spend-ux`, `Spend-rename`, `Spend-abuse` (half-made, empty)
- `~/Developer/Sortd-partial-leftover` (pieces of an interrupted move; all identical to the repo)
- A safety hook blocks `rm -rf` under the home folder, so Raj deletes these himself.

## 2. Branches: what is still not in `main`

Counted with `git cherry main <branch>` (compares changes, not commit ids). A "not in main" commit
may still have been redone differently in `ux-refresh` — check the diff before merging anything.

| Branch | Worktree | Not in main | Uncommitted | What it is |
|---|---|---|---|---|
| `ux-refresh` | yes | 14 | 4 untracked | **Newest code.** Onboarding + UI polish. 369 tests passed (other session's count). Pushed to GitHub 24 Sep. |
| `rename-sortd` | yes | 14 + rename | — | `ux-refresh` + Spend→Sortd rename (section 3). |
| `abuse-findings` | yes | 15 | — | `ux-refresh` + the abuse tests (commit `d5b6afb`, pushed). Fails on purpose until fixed. |
| `beta-rc1` | yes | 14 of 21 | 87 untracked (Roadmap.md, QA screenshots) | Merges copy-trim and more. |
| `copy-trim` | yes | 8 of 12 | 14 untracked (screenshots) | Copy trimming. |
| `forwarding-inbox` | yes | 10 | — | Cloudflare email-forwarding inbox. **Not deployed, not wired into Settings.** See `docs/ForwardingInbox.md` on that branch. |
| `launch-screen` | yes | 6 of 10 | 17 changes (1,035 screenshot files) | Branded launch screen, rework in progress. |
| `pull-refresh` | yes | 6 of 10 | 1 | Pull-to-refresh + confetti. |
| `speed-loading` | yes | 6 of 10 | 1 | Faster Gmail connect/sync. |
| `paywall-steps` | yes | 5 of 9 | 19 changes | Paywall rework in progress (PaywallModel, tests). |
| `tapfix` | no | 1 | — | "Never drop a real Apple Pay tap". Check whether `ux-refresh` already covers it. |
| `beta-ops` | yes | 1 | — | Crash reporting, preflight flag check. |
| `pro-beta-offer-codes` | no | 1 | — | Free beta Pro, offer codes. |
| `settings-redesign` | yes | 0 | 1 untracked | Already in main. |
| `beta-prep` | no | 0 | — | **Stale** — 27 behind main. Old CLAUDE.md said branch from it; the new one says `main`. |
| `ci-tests`, `claude/objective-banach-827182`, `worktree-agent-*` | no | 0–1 | — | Dead or duplicates of the above. Delete after checking. |

## 3. The Spend → Sortd rename (branch `rename-sortd`, commit `35c3e45`, pushed, NOT merged)

Built on `ux-refresh`. Changes: folders `Spend/`→`Sortd/`, `SpendTests/`→`SortdTests/`,
`Spend.xcodeproj`→`Sortd.xcodeproj`, scheme/target/module `Spend`→`Sortd`, `SpendApp`/`SpendStore`/
`SpendMigrationPlan`→`Sortd…`, all `SPEND_*` debug env vars→`SORTD_*`, and **bundle IDs**
`com.kameshraj.spend*`→`com.kameshraj.sortd*` (app, widget, tests, app group, Keychain service,
StoreKit product ids, logger). Words about money (`SpendCategory`, `SpendSummary`, "Spend less") stay.

Test result on the rename (24 Sep): **all 369 tests pass** on a fresh simulator (`Sortd-rename`),
Release build succeeds. First run on a brand-new simulator fails the 6 StoreKit tests — known, passes
on re-run. A first attempt failed `matchesWalletNames` because the scheme still set `SPEND_IN_MEMORY`;
fixed in the commit. The CI workflow is renamed too.

**Before the rename ships (Raj's actions, outside the code):**
1. **Apple Pay shortcut:** `scripts/build-apple-pay-shortcut.py` now targets `com.kameshraj.sortd`.
   Rebuild and re-sign `site/apple-pay.shortcut`, deploy the site, and every user must re-download it.
   Until then the live shortcut only works with the old app.
2. **Google OAuth:** the iOS OAuth client in Google Cloud is registered to `com.kameshraj.spend`.
   Update it to `com.kameshraj.sortd`. Unverified: whether this touches the restricted-scope review
   submitted 20 Sep — check before changing.
3. **App Store Connect:** register the App ID and the three Pro product ids with the new prefix.
4. Anyone with an older build loses their data, Keychain token and widget data (new app container).
   Fine now — no TestFlight testers yet.
5. Every other branch still uses `Spend/` paths. Merge them **before** the rename, or expect conflicts.

## 4. Open work and decisions (in order)

1. **PR #8 is open: `rename-sortd` → `main`** (https://github.com/kameshraj912/sortd/pull/8, opened 24 Sep).
   It carries all of `ux-refresh` plus the rename, so it replaces a separate `ux-refresh` PR. All 369
   tests passed locally (StoreKit on re-run). Not merged — Raj merges it once CI is green. Note item 5
   below: merging the rename now means the old branches will conflict on `Spend/` paths. Raj chose
   to open it anyway, so old branches get ported onto the renamed paths, not merged as they are.
2. **Abuse findings:** 21 findings in `SpendTests/AbuseMoneyAgentTests.swift` and
   `AbuseDataAgentTests.swift`, committed on `abuse-findings` (`d5b6afb`, pushed). One confirmed
   wrong-money bug: currency guessed from letters inside a merchant name. Fix them, then move the tests
   to `main`. Copies are still untracked in the `ux-refresh` worktree — and because the project uses
   folder-synced groups, **they get compiled into any `ux-refresh` test run there** (445 tests, ~50
   failures). Delete those two untracked copies before trusting a `ux-refresh` test run.
3. **Apple Pay auto-log real-world test:** the fixed shortcut went live after Raj's vending-machine
   test. Raj must re-download the shortcut (Replace), then pay at a staffed till. Decides whether the
   fix works or it is Apple's timeout.
4. Triage the old branches in section 2 (merge or drop), then delete dead branches and worktrees.
5. After PR #8 merges, do the section 3 outside steps.
6. **Next big task (Raj's request):** one main Claude chat with expert agents under it (testing,
   simulator, abuse/security, debugging, release, growth) plus a fixed pipeline script
   (build → tests → preflight), covering the whole app lifecycle. Build it on `main` after PR #8.
7. Undecided: Sentry, privacy-policy naming, UI adversarial pass (never ran), AX5 visual check,
   backup (CloudKit, not built), `SORTD_BETA` removal before App Store.
8. Flaky test seen 23 Sep: `matchesWalletNames` (YouTrip/Maybank) failed once on a reused simulator;
   StoreKit tests fail on a brand-new simulator's first run, pass on re-run.

## 5. Disk
- Free: ~74 GB. Big items: simulators 43 GB (`xcrun simctl delete unavailable`, old clones like
  `Sortd-ux-Max`, `Sortd-ux-SE`, `Sortd-rename`), old iOS DeviceSupport 13 GB.
- Build folders to delete when done: `.claude/worktrees/rename-sortd/build` (7.1 GB),
  `.claude/worktrees/ux-refresh/build` (3.6 GB), and `/tmp/claude-501/dd-rename*` (7 GB).
- Each `derivedDataPath` is ~3.5 GB. Put it inside the worktree (`build/dd`, gitignored) and delete it
  when the branch is done.

## 6. Traps (so they are not repeated)
- Don't put git repos in iCloud folders. Don't wrap iCloud downloads in wait loops (the auto-mode
  classifier blocks it). Check cloud-only files with `find -flags +dataless` (the `+` matters).
- Don't give two agents the same worktree or simulator.
- Verify which checkout an agent looked at — earlier research agents surveyed the wrong one.

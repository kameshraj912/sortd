# Sortd — handover

Written 25 September 2026, after the free-app overhaul (PRs #30–#41).
Read `docs/AgentPipeline.md` first: it is the working bible for how work gets done here.
Everything below was verified, not assumed — where I could not verify something, it says so.

## 1. Where things are

| | |
|---|---|
| Repo | `/Users/kameshraj/Developer/Sortd` (folder on disk is still named `Spend`; the product is Sortd) |
| Branch | `main` @ `18a2d1c` (`git rev-parse --short origin/main`, 25 Sep) |
| Tests | **733** at PR #41 — this is the figure I was given for this handover; I read PR #41's body directly and it does **not** state a total, only its own new suites (TipRulesTests 29, TipCopyTests 6, TipStateTests 13). Total run count **not verified** by me. |
| Known bugs | **21**, from the pre-overhaul baseline (`docs/ux-research/baseline-2026-09-25/README.md`, `scripts/test.sh --known-bugs` on commit `c379a0e`). Confirmed unchanged through the overhaul: sub-spec 1's and 8's gates both require the count not to rise, and PR #41's body says "known-bug set unchanged from baseline (21)". I did not re-run the script myself (docs-only task, no builds). |
| CI | GitHub Actions minutes were exhausted on 25 Sep. Every PR since #30 was gated locally instead: `scripts/check.sh --all` (build + full test run + known-bugs + StoreKit) plus a by-hand comparison of the known-bug test **names** against the baseline list, since CI could not be trusted to run. I spot-checked three of the actual CI check runs (#30, #33, #41): #33 shows a normal green run; #30 and #41 show the **build** step itself failing after real minutes were spent (not a "skipped, no runner" state) — so "CI minutes exhausted" explains why CI could not be relied on, but I could not independently confirm from the run logs that exhaustion (rather than a real build issue) is why those two specific runs are red. Take the local gate as the source of truth, per the PR bodies. |
| Pipeline | `docs/AgentPipeline.md` — agents in `.claude/agents/`, skills `sortd-*`, scripts in `scripts/`. This is the working bible; it now also has a "Lessons from the first overhaul" section (see below). |

## 2. What shipped in the overhaul

Nine sub-specs planned in `docs/specs/2026-09-25-free-app-overhaul-overview.md` (approved by Raj 25 Sep). Eight shipped; one is still open.

**1 — Free, tip jar** (PR #30, docs follow-up PR #31). Removes `ProStore`, `CompedPro`, `PaywallView`, `SecretCodeSheet`; adds `Services/TipJar.swift`, `Settings/TipJarView.swift`, `SortdTips.storekit`. `SORTD_BETA` is gone (confirmed: not in `project.pbxproj` any more). No compile flag — nothing is gated, everything is unlocked. **Not verified:** the three tip consumables exist in App Store Connect (blocked on Raj, see §4).

**2 — Analytics** (PR #33). `Services/Analytics.swift`, consent switch in Settings › Privacy. Keyed by `POSTHOG_API_KEY`/`POSTHOG_HOST` (see §3). No compile flag; PostHog feature flags are used for A/B only. Signed-in identity is `sha256(accountSalt + provider + subject)` — see the `accountSalt` trap below. **Not verified:** real PostHog project, region, autocapture audit.

**2b — Crash reports (Sentry, live)** (PR #36). `Services/CrashReporting.swift`, keyed by `SENTRY_DSN`. Shares the analytics consent switch — crash reports are off if consent is off, if the DSN is empty, or in DEBUG builds (confirmed in `CrashReporting.swift`: three separate `log.notice("crash reports off: …")` guards). No compile flag. **Not verified:** a real DSN, "Prevent storing IP addresses" being set server-side, the forced-crash check.

**3 — iCloud backup** (PR #32). `Services/CloudBackup.swift`, `Settings/BackupDataSettingsView.swift`, `Spend.entitlements`. Behind the **`SORTD_ICLOUD`** compile flag — confirmed off in both Debug and Release in `project.pbxproj` (the flag string does not appear anywhere in the file). `CloudBackup` itself and its tests (fakes only) compile and run regardless; only the Settings section, save hook, scene-phase backup and the Delete All Data step are compiled out. Chose option A (snapshot to CloudKit private DB), not live sync — see §7. **Not verified:** device, real iCloud account, a real restore round-trip (the sub-spec's own gate requires this on a real device).

**4 — Sign-in (Apple or Google)** (PR #39; spec drafted in PR #35; Worker implemented in PR #38). `Services/AccountStore.swift`, `GoogleAuth.swift`, `Settings/AccountSettingsView.swift`, `Spend.entitlements`. Behind the **`SORTD_SIGNIN`** compile flag — also confirmed off in both configs. Keyed by `ACCOUNT_WORKER_URL` (see §3). `AccountStore` and its providers always compile; only the account screen and its Settings row are gated. **Not verified:** real device, App Attest against a real key, real Apple/Google accounts, the Worker's production secrets.

**5 — Motion** (PR #34). `Components/Feedback.swift`, one haptic map across 14 files, direction-aware transitions. The day-by-day Activity pager is behind the DEBUG-only **`SPEND_ACTIVITY_DAYS`** env var (`ActivityView.swift`); the list view stays the default until the pager gets its own UI pass.

**6 — Onboarding** (PR #37). `SetupFlow.swift`, tap-through setup with sensible defaults, the activation moment. Behind the DEBUG-only **`SPEND_NEW_SETUP`** env var (`SetupFlow.usesNewFlow`); the old flow is still the shipped default. Flag removal is a follow-up PR (§5).

**7 — Tips (TipKit)** (PR #41). `Components/Tips.swift`, six tips, one on screen at a time, pure eligibility rules. **`SPEND_TIPS_NOW`** is a DEBUG convenience only (skips the first-session wait and visit counts so a tip shows immediately for testing) — the tips themselves ship unconditionally, there is no feature flag gating them. Review found one must-fix (an off-screen Apple Pay tip blocking the month tip) and five should-fixes, both applied per the PR body.

**8 — Instant** (PR #40). Undo for category moves, suggestions, budget pace, outcomes. No compile flag. Gate required known-bug count not to rise — confirmed still 21.

**9 — Brand** (in progress, no PR yet). Icon renders and new store screenshots. What exists: flat-PNG app icon with light/dark/tinted appearances, `Brand/icon-source/*.html`, locked wordmark and colours (`Brand/README.md`). Missing: a layered Icon Composer icon for proper Liquid Glass rendering. **Waiting on Raj to approve the icon renders** (§4).

## 3. Secrets and switches

**`Secrets.xcconfig`** (gitignored; copy from `Secrets.xcconfig.example`, next to `Config.xcconfig`; `#include?` means a missing file never breaks the build):

| Key | Empty behaviour |
|---|---|
| `POSTHOG_API_KEY` | Analytics off. Logs `"analytics off: no key (POSTHOG_API_KEY is empty), nothing is sent"` once. The key is write-only (`phc_...`) — a leak allows fake events, not reads. |
| `POSTHOG_HOST` | Defaults to `https://eu.i.posthog.com` in `Config.xcconfig` even if unset. |
| `SENTRY_DSN` | Crash reports off. Logs `"crash reports off: no DSN (SENTRY_DSN is empty)"`. Also off in DEBUG builds and when analytics consent is off, regardless of the DSN. |
| `ACCOUNT_WORKER_URL` | Account deletes are queued on the phone (hash only) and retried at the next launch, instead of calling the Worker immediately. |

**Worker secrets** (`worker/README.md`, `cd worker && npx wrangler secret put <NAME>`, repeat with `--env dev` for the dev environment — secrets are not shared between environments):
`APPLE_TEAM_ID`, `APPLE_CLIENT_ID` (`com.kameshraj.spend`), `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY` (piped in from the `.p8`), `POSTHOG_API_KEY` (the personal `phx_...` key, not the app's `phc_...` one), `POSTHOG_PROJECT_ID`, `CHALLENGE_KEY` (random, `openssl rand -base64 32`). Dev only: `DEV_BYPASS_TOKEN`, which also has to go in the app's DEBUG xcconfig and must never reach the prod Worker.

**Compile flags** (Xcode → Spend target → Build Settings → Active Compilation Conditions → add to both Debug and Release). Confirmed all three below are absent from `project.pbxproj` today — nothing is turned on yet:

- **`SORTD_ICLOUD`** — needs paid enrolment first, then the iCloud capability on the App ID.
- **`SORTD_SIGNIN`** — needs paid enrolment first, then the Sign in with Apple capability on the App ID (the entitlement is already listed in `Spend.entitlements`; without the capability the Apple button fails at runtime with error 1000).
- `SORTD_GMAIL` is already on in Release (`SWIFT_ACTIVE_COMPILATION_CONDITIONS = "SORTD_GMAIL $(inherited)"`) — unrelated to the overhaul, listed here only so the other two aren't mistaken for it.

Enrolment is the blocker for both of the above — see §4.

## 4. Only Raj can do these

1. **GitHub Actions minutes.** Exhausted 25 Sep; CI cannot be relied on until this is sorted (billing/plan, not something I have access to check from here).
2. **PostHog project**: create it, get the project key, pick the region (default assumed EU per the overview spec, **not verified** as actually created), and turn on **Discard client IP data**.
3. **Sentry DSN**: create the project, get the DSN for `Secrets.xcconfig`, and turn on **Prevent storing IP addresses** (Settings › Security & Privacy) so the server side matches the app's `sendDefaultPii = false`.
4. **App Store Connect**: create the three tip consumables (sub-spec 1's gate needs these before any store build).
5. **Paid Apple Developer enrolment**, then the **iCloud**, **Sign in with Apple**, and **App Attest** capabilities on the App ID — this unblocks sub-specs 3 and 4 and the two compile flags above.
6. **A Sign in with Apple key (.p8)**: Apple Developer → Keys → new key → Sign in with Apple, configured for `com.kameshraj.spend`. Downloads once — save it. Note the Key ID and Team ID. Then run the `wrangler secret put` list in §3.
7. **Approve the icon renders** for sub-spec 9 (still in progress — no PR yet).
8. **Retest Apple Pay at a staffed till** (carried over from the last handover — the vending-machine test used the pre-fix shortcut; nobody has retested the fixed one on a real device). Steps unchanged: Sortd → Apple Pay step → Get the Shortcut → Replace → buy something small on a Visa at a staffed till, not a vending machine → check Settings → Purchase Sources → Apple Pay Logging → Last Tap Received.

The disputed-tests item from the last handover is closed: of the 30 abuse findings from the 24 Sep run, 1 was fixed and Raj had 7 deleted as disputed, leaving the 21 in the current baseline. Nothing open there.

## 5. Still to do

- **Sub-spec 9 screenshots** — new App Store screenshot set, once the icon renders are approved.
- **Live Activities** (Gmail sync progress, monthly budget) and **Share Extension** (share a receipt into Sortd) — each needs a new app target, so each gets its own spec first. Not started.
- **UI pass after the overhaul**: see `docs/UIPass-2026-09-25.md` — this file does **not exist yet** (confirmed); it is the planned follow-up to `docs/UIPass-2026-09-24.md`, and the router is expected to fill in the counts once it runs.
- **CloudKit live sync (option B)**, if Raj wants it — its own migration-first sub-spec, see §7.
- **Flag removals** for `SORTD_ICLOUD`, `SORTD_SIGNIN`, `SPEND_NEW_SETUP` and `SPEND_ACTIVITY_DAYS` once each has had its own UI pass and Raj has approved making it the default.

## 6. Traps — read before spending a day on these

Carried over, still true:

- **Two research agents surveyed the wrong checkout once** and reported a P0 that did not exist on the branch being worked on. Always verify an agent's survey against the actual worktree before acting.
- **Do not give several agents the same worktree.** Test files land in the shared `SpendTests/`; one half-written file breaks every build.
- **One simulator per worktree**, or sessions fight over it (`scripts/worktree-new.sh` clones one per task automatically).
- **StoreKit tests are simulator-dependent.** Use the iOS 27 simulator, not iOS 26.x. New this round: they also flake right after a simulator has just booted — if one fails immediately after boot, rerun it alone before assuming it's a real failure.
- **Apple doc bugs.** `.searchToolbarBehavior(.minimize)`, not `.minimized`; `toolbarMinimizationBehavior(_:for:)`, not `toolbarMinimizeBehavior`.
- **Disk.** Each `derivedDataPath` is ~3.5 GB; `scripts/clean.sh --yes` frees it.

New from this overhaul:

- **CI pins Xcode 26.6; local is 27.** An SDK-only symbol needs `#if compiler(>=6.4)`, not just `#available`. This bit the pipeline once already (`accessibilityPrefersCrossFadeTransitions`); check for the same pattern in new SDK-only APIs.
- **Zero-width characters in test log lines break naive name comparisons.** The known-bug gate compares test names from `scripts/test.sh --known-bugs` output against the baseline list by hand; a plain string match can silently fail on copy-pasted names.
- **zsh does not word-split unquoted variables in loops.** A `for x in $list` that relies on bash-style word-splitting will not iterate the way it does in bash — quote or use an array.
- **The analytics `accountSalt`** (`Analytics.swift:91`) is one fixed string compiled into the app, on purpose — it is what makes the signed-in PostHog id the same across reinstalls and phones. Do not treat a hardcoded salt here as a bug to fix.
- **`Backup.restore` inserts `Transaction` rows directly** (`Backup.swift:379`), by design — it is restoring rows the logger already checked once, not new data. `CLAUDE.md` names only `DemoData` as allowed to bypass `TransactionLogger`; this is a known, accepted exception, not an oversight.

## 7. Decisions still open

1. **Privacy policy entity.** Whether it names a person or a business entity. Needs a lawyer (per the overhaul's own "for a lawyer" line: EU consent and the policy name).
2. **Site copy.** Being redone separately from the app; its privacy page must match the App Privacy label before App Store submission.
3. **CloudKit option A vs live sync (option B).** Shipped: option A, a snapshot to the CloudKit private DB (reuses the tested `Backup.Snapshot` format and restore path, no model change). Option B — `ModelConfiguration` with CloudKit, live sync across devices — is deferred; it needs its own migration-first sub-spec (it would drop `.unique` in a `SchemaV2`) and ships alone if Raj wants it.

---

*Things I could not verify from this worktree, listed together: the 733 test count at PR #41 (not in the PR body); the CI-minutes-exhausted explanation for the two red build checks I sampled (#30, #41 — the jobs did run and spend real minutes before failing, which I could not reconcile with "exhausted" from the logs alone); anything needing a device, a real account, a real PostHog/Sentry project, or App Attest against real hardware; whether the App Store Connect tip products already exist.*

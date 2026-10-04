# Sortd — handover

Written 25 September 2026, after the free-app overhaul (PRs #30–#41). Refreshed 26 September
2026 for TestFlight prep (see §0).
Read `docs/AgentPipeline.md` first: it is the working bible for how work gets done here.
Everything below was verified, not assumed — where I could not verify something, it says so.

## 0. What changed on 26 Sep 2026

- **The paid Apple Developer account is active** (team `7CLGYQ9P3L`). The App ID has iCloud,
  Sign in with Apple and App Attest. Both configs sign with `Spend.entitlements`
  (`Spend-Development.entitlements` is no longer used by the project).
- **`SORTD_SIGNIN` and `SORTD_ICLOUD` are ON** in Debug and Release (PR #69, commit `2e0519a`;
  confirmed in `project.pbxproj`). Sign-in and iCloud backup ship in the next build.
- **The SwiftData store stays `cloudKitDatabase: .none`** (commit `ccd2871`). With the iCloud
  entitlement, the default would mirror the store to CloudKit and crash at launch on the unique
  keys. iCloud backup is `CloudBackup`'s own record, not store sync.
- **PostHog and Sentry keys exist** and live only in the gitignored `Secrets.xcconfig` on Raj's
  Mac (`POSTHOG_API_KEY`, `POSTHOG_HOST`, `SENTRY_DSN`). A checkout without that file builds with
  analytics and crash reports off. Reported by the pipeline session, not verified from this
  checkout: the PostHog project is on the **US** cloud, so `POSTHOG_HOST` in `Secrets.xcconfig`
  must override the EU default in `Config.xcconfig`.
- **The account Worker is not deployed** and its secrets are not set. Until it is, account
  deletes queue on the phone (hash only) and retry at the next launch. `*.p8` is now gitignored.
- **TestFlight text** is in `docs/TestFlightWhatToTest.md`. `docs/AppReviewNotes.md` has the
  contact name and email filled; phone, video link and the test Gmail account are still Raj's.
- **GitHub Actions minutes are exhausted until 1 Oct** (reported by the pipeline session), so CI
  shows failed on new PRs. The local gate (`scripts/check.sh --all`) stands in until then.

## 1. Where things are

| | |
|---|---|
| Repo | `/Users/kameshraj/Developer/Sortd` (folder on disk is still named `Spend`; the product is Sortd) |
| Branch | `main` @ `8ec8123` (`git rev-parse --short origin/main`, 26 Sep, PR #71) |
| Tests | **733** at PR #41 — this is the figure I was given for this handover; I read PR #41's body directly and it does **not** state a total, only its own new suites (TipRulesTests 29, TipCopyTests 6, TipStateTests 13). Total run count **not verified** by me. |
| Known bugs | **21**, from the pre-overhaul baseline (`docs/ux-research/baseline-2026-09-25/README.md`, `scripts/test.sh --known-bugs` on commit `c379a0e`). Confirmed unchanged through the overhaul: sub-spec 1's and 8's gates both require the count not to rise, and PR #41's body says "known-bug set unchanged from baseline (21)". I did not re-run the script myself (docs-only task, no builds). |
| CI | Green on `main` at PR #42 (Xcode 26.6, 733 tests). The Actions quota ran out in the small hours of 25 Sep (GitHub: "job was not started"), so PRs #30 to #41 were gated locally: `scripts/check.sh --all` plus a comparison of the failing known-bug test **names** against the baseline list. Minutes came back during the day; the first CI runs then failed the **build** step on Xcode 26.6 (`Activation.swift`: a generic-inference difference between Swift 6.4 locally and 6.2 on the runner) and one sign-in test that compared JSON key order. Both fixed in PR #42. Lesson: local Xcode 27 is not proof; CI on the pinned Xcode is. |
| Pipeline | `docs/AgentPipeline.md` — agents in `.claude/agents/`, skills `sortd-*`, scripts in `scripts/`. This is the working bible; it now also has a "Lessons from the first overhaul" section (see below). |

## 2. What shipped in the overhaul

Nine sub-specs planned in `docs/specs/2026-09-25-free-app-overhaul-overview.md` (approved by Raj 25 Sep). Eight shipped; one is still open.

**1 — Free, tip jar** (PR #30, docs follow-up PR #31). Removes `ProStore`, `CompedPro`, `PaywallView`, `SecretCodeSheet`; adds `Services/TipJar.swift`, `Settings/TipJarView.swift`, `SortdTips.storekit`. `SORTD_BETA` is gone (confirmed: not in `project.pbxproj` any more). No compile flag — nothing is gated, everything is unlocked. **Not verified:** the three tip consumables exist in App Store Connect (blocked on Raj, see §4).

**2 — Analytics** (PR #33). `Services/Analytics.swift`, consent switch in Settings › Privacy. Keyed by `POSTHOG_API_KEY`/`POSTHOG_HOST` (see §3). No compile flag; PostHog feature flags are used for A/B only. Signed-in identity is `sha256(accountSalt + provider + subject)` — see the `accountSalt` trap below. **Not verified:** real PostHog project, region, autocapture audit.

**2b — Crash reports (Sentry, live)** (PR #36). `Services/CrashReporting.swift`, keyed by `SENTRY_DSN`. Shares the analytics consent switch — crash reports are off if consent is off, if the DSN is empty, or in DEBUG builds (confirmed in `CrashReporting.swift`: three separate `log.notice("crash reports off: …")` guards). No compile flag. **Not verified:** a real DSN, "Prevent storing IP addresses" being set server-side, the forced-crash check.

**3 — iCloud backup** (PR #32). `Services/CloudBackup.swift`, `Settings/BackupDataSettingsView.swift`, `Spend.entitlements`. Behind the **`SORTD_ICLOUD`** compile flag — **on in both Debug and Release since 26 Sep 2026** (was off at the 25 Sep handover). `CloudBackup` itself and its tests (fakes only) compile and run regardless; only the Settings section, save hook, scene-phase backup and the Delete All Data step are compiled out. Chose option A (snapshot to CloudKit private DB), not live sync — see §7. **Not verified:** device, real iCloud account, a real restore round-trip (the sub-spec's own gate requires this on a real device).

**4 — Sign-in (Apple or Google)** (PR #39; spec drafted in PR #35; Worker implemented in PR #38). `Services/AccountStore.swift`, `GoogleAuth.swift`, `Settings/AccountSettingsView.swift`, `Spend.entitlements`. Behind the **`SORTD_SIGNIN`** compile flag — **also on in both configs since 26 Sep 2026**. Keyed by `ACCOUNT_WORKER_URL` (see §3). `AccountStore` and its providers always compile; only the account screen and its Settings row are gated. **Not verified:** real device, App Attest against a real key, real Apple/Google accounts, the Worker's production secrets.

**5 — Motion** (PR #34). `Components/Feedback.swift`, one haptic map across 14 files, direction-aware transitions. Activity was a day-by-day pager from 25 Sep to 3 Oct 2026. Since 3 Oct 2026 it is one scrolling list of every day again (`docs/specs/2026-10-03-activity-rebuild.md`, option B): a rounded card per day under the day's name and total, search and filters across every day, and "Go to Date…" in the filter menu (`ActivityDays.swift`). The pager stays in for the DEBUG-only **`SPEND_ACTIVITY_PAGER=1`** escape, for one comparison on the phone, then goes.

**6 — Onboarding** (PR #37). `SetupFlow.swift`, tap-through setup with sensible defaults, the activation moment. The default since 25 Sep 2026 (`SetupFlow.usesNewFlow` is true; the ActivationCard, `Activation.watchSaves` and the setup copy follow it). The old flow stays in for the DEBUG-only **`SPEND_OLD_SETUP=1`** escape. `Activation.settleExistingInstall` still marks an install that finished the old setup as already asked.

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

**Compile flags** (Xcode → Spend target → Build Settings → Active Compilation Conditions). As of 26 Sep 2026, `project.pbxproj` has:

- Debug: `DEBUG SORTD_SIGNIN SORTD_ICLOUD SORTD_REPLAY`
- Release: `SORTD_SIGNIN SORTD_ICLOUD` (checked 4 Oct 2026; `SORTD_GMAIL` went with Gmail on 2 Oct, `SORTD_REPLAY` left Release in #114)

`SORTD_ICLOUD` and `SORTD_SIGNIN` went on in PR #69 once the paid account and the App ID capabilities were in place. Nothing is blocked on enrolment any more.

## 4. Only Raj can do these

1. **GitHub Actions minutes.** The quota ran out once on 25 Sep and came back the same day. Decide the standing fix: a small spending limit on the card, a public repo, or a self-hosted runner. Until then a heavy day can exhaust it again.
2. **PostHog project**: done, key in `Secrets.xcconfig` on Raj's Mac (26 Sep). Still to check: **Discard client IP data** is on, and `POSTHOG_HOST` points at the US cloud if that is where the project is.
3. **Sentry DSN**: done, DSN in `Secrets.xcconfig` on Raj's Mac (26 Sep). Still to check: **Prevent storing IP addresses** (Settings › Security & Privacy) so the server side matches the app's `sendDefaultPii = false`.
4. **App Store Connect**: create the three tip consumables (sub-spec 1's gate needs these before any store build).
5. ~~Paid Apple Developer enrolment and the App ID capabilities~~ — done 26 Sep 2026 (team `7CLGYQ9P3L`).
6. **A Sign in with Apple key (.p8)** and the **account Worker deploy**: Apple Developer → Keys → new key → Sign in with Apple, configured for `com.kameshraj.spend`. Downloads once — save it outside the repo (`*.p8` is gitignored). Note the Key ID and Team ID. Then run the `wrangler secret put` list in §3 and deploy from `worker/`.
9. **App Review contact phone, the Shortcuts video and the test Gmail account** for `docs/AppReviewNotes.md`, and the TestFlight text from `docs/TestFlightWhatToTest.md` into App Store Connect.
7. **Approve the icon renders** for sub-spec 9 (still in progress — no PR yet).
8. **Retest Apple Pay at a staffed till** (carried over from the last handover — the vending-machine test used the pre-fix shortcut; nobody has retested the fixed one on a real device). Steps unchanged: Sortd → Apple Pay step → Get the Shortcut → Replace → buy something small on a Visa at a staffed till, not a vending machine → check Settings → Purchase Sources → Apple Pay Logging → Last Tap Received.

The disputed-tests item from the last handover is closed: of the 30 abuse findings from the 24 Sep run, 1 was fixed and Raj had 7 deleted as disputed, leaving the 21 in the current baseline. Nothing open there.

## 5. Still to do

- **Sub-spec 9 screenshots** — new App Store screenshot set, once the icon renders are approved.
- **Live Activities** (Gmail sync progress, monthly budget) and **Share Extension** (share a receipt into Sortd) — each needs a new app target, so each gets its own spec first. Not started.
- **UI pass after the overhaul** (`docs/UIPass-2026-09-25.md`, done 25 Sep): no P0, 3 P1 (bank names cut to letters at AX5 in setup; the "Moved N others · Undo" toast missing in 2 of 3 tries; setup choices hyphenated at AX5), 6 P2, 3 P3. Nothing that exists in both screenshot sets got worse. Fix the P1s first, through `sortd-build`.
- **CloudKit live sync (option B)**, if Raj wants it — its own migration-first sub-spec, see §7.
- **Flag removals.** Done 25 Sep 2026: the tap-through setup is the default (the DEBUG escape `SPEND_OLD_SETUP=1` keeps the old path for comparison; the Activity pager was undone on 3 Oct 2026 and sits behind DEBUG `SPEND_ACTIVITY_PAGER=1`), and `AppIcon-Glass.icon` is the active icon pending Raj's look on the phone. `SORTD_ICLOUD` and `SORTD_SIGNIN` are on since 26 Sep 2026 (PR #69); the flags stay in the code as build-time switches only.

## 6. Traps — read before spending a day on these

Carried over, still true:

- **Two research agents surveyed the wrong checkout once** and reported a P0 that did not exist on the branch being worked on. Always verify an agent's survey against the actual worktree before acting.
- **Do not give several agents the same worktree.** Test files land in the shared `SpendTests/`; one half-written file breaks every build.
- **One simulator per worktree**, or sessions fight over it (`scripts/worktree-new.sh` clones one per task automatically).
- **StoreKit tests are simulator-dependent.** Use the iOS 27 simulator, not iOS 26.x. New this round: they also flake right after a simulator has just booted — if one fails immediately after boot, rerun it alone before assuming it's a real failure.
- **Apple doc bugs.** `.searchToolbarBehavior(.minimize)`, not `.minimized`; `toolbarMinimizationBehavior(_:for:)`, not `toolbarMinimizeBehavior`.
- **Disk.** Each task holds ~4 GB of build folder and ~7 GB of simulator. Every session
  ends with `scripts/worktree-done.sh <task>` (merged) or `scripts/worktree-park.sh <task>`
  (PR still open); `scripts/clean.sh --yes` sweeps up the rest. Rule: CLAUDE.md "6. Finish".

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

*Things I could not verify from this worktree, listed together: anything needing a device, a real account, a real PostHog/Sentry project, or App Attest against real hardware; whether the App Store Connect tip products already exist.*

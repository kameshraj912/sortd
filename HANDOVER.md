# Sortd — handover

Last updated 24 September 2026, morning. Written for whoever picks this up next.
Read `docs/AgentPipeline.md` first: it is how work gets done here now.
Everything below was verified, not assumed — where I could not verify
something, it says so.

## Where things are

| | |
|---|---|
| Repo | `/Users/kameshraj/Developer/Sortd` (moved here from `~/Documents/Spend`) |
| Branch | `main` @ `ed752cc` — **pushed**, CI green, nothing outstanding |
| Tests | **445 passing**, 23 known bugs skipped, 468 in the run; measured with `scripts/test.sh` on 24 Sep (`--known-bugs` runs the 29, `--storekit` adds ProStoreTests) |
| Pipeline | `docs/AgentPipeline.md` · agents in `.claude/agents/` · skills `sortd-*` · scripts in `scripts/` |

Branches still holding work (`scripts/worktree-audit.sh` shows the live picture; all
are pushed to origin now, and `docs/AgentPipeline.md` says why none should be merged whole):

- **Ported to `main` overnight on 24 Sep** (each through its own PR, CI green): the
  preflight debug-flag check, the static launch screen and "App Lock off"
  (`launch-screen`), beta Pro cached + Redeem Code + `BetaAccessTests` (`358c363`),
  the faster Gmail sync with `SyncStatus`, `Perf` and Gmail tests (`speed-loading`),
  and the abuse findings as known-bug tests (`abuse-findings`).
- **Raj's call, not merged:** `forwarding-inbox` (6,300 lines: a Cloudflare Worker
  that receives forwarded receipts, not wired into the app), `paywall-steps` (a
  multi-step paywall, now committed, depends on `isBetaFree` which main has since),
  confetti and `RefreshCoordinator` in `pull-refresh`, `LaunchOverlay` in
  `launch-screen`, and PR #8 `rename-sortd` (only the `Spend/`→`Sortd/` folder rename
  is not on main; the PR conflicts and would undo the CI fix, so redo it fresh if wanted).
- **Nothing left to port:** `ux-refresh`, `settings-redesign`, `copy-trim`, `beta-ops`,
  `beta-rc1` (a merge of the others). Their worktrees hold only screenshot folders.
- `beta-prep` is retired. The base branch is `main`.

---

## What got done

### 25 Sep — the free-app overhaul, starting

Raj decided to remove Pro and make the whole app free, with a tip jar. Nine sub-specs,
ship order and gate for each: `docs/specs/2026-09-25-free-app-overhaul-overview.md`.

### 24 Sep, overnight — the agent pipeline, and the old branches sorted

- **CI was red** on every push since 23 Sep. One cause: `accessibilityPrefersCrossFadeTransitions`
  only ships in the Xcode 27 SDK and GitHub's `latest-stable` was Xcode 26.6. Fixed with a
  `#if compiler(>=6.4)` guard; CI now pins Xcode 26.6 (PR #9).
- **Scripts and hooks** (PR #10): `scripts/worktree-new.sh`, `worktree-done.sh`, `build.sh`,
  `test.sh`, `sim.sh`, `worktree-audit.sh`, `clean.sh`; pre-commit blocks secrets, big files,
  debug flags outside `#if DEBUG`; pre-push refuses direct pushes to `main`. GitHub branch
  protection is refused on this private repo without a paid plan (Raj has the Student plan;
  the benefit is not active on the account).
- **Ten agents** in `.claude/agents/` (PR #11) and **ten skills** `sortd-idea` … `sortd-status`
  plus the `bug-hunt` workflow and `docs/testing/attacks.md` (PR #12).
- **The abuse findings are on `main`** as known-bug tests, 29 of them, CI green (PR #13). The
  currency substring bug is fixed.
- **Ports from old branches** (PRs #14, #15, #16), listed under "Where things are".
- **The UI adversarial pass ran** (PR #17, `docs/UIPass-2026-09-24.md`): no crashes, 2 P1,
  11 P2, 3 P3. See "Still to do → 2".

### The Apple Pay bug — fixed

Raj reported that real Apple Pay taps logged nothing.

**Root cause:** the ready-made shortcut's field mappings were **silently dropped
on import**. A parameter written as a bare `WFTextTokenAttachment` is discarded
by Shortcuts. It has to be a `WFTextTokenString` holding the variable as an
attachment at position 0. Confirmed by importing the file on an iOS 26.4
simulator before and after — every field came back a grey placeholder before,
intact after.

**Design now: one mapping only.** A Text action holds the whole Shortcut Input
and passes it to the intent's `transaction` parameter, where
`WalletTapText.parse` splits it.

> The three property mappings (Amount, Merchant, Card or Pass) do survive import
> now, but their property *sub-selection* does not — so all three would receive
> the whole transaction and the shop name would be a blob.
> **Do not re-add them without testing on a real device.**

- Builder: `scripts/build-apple-pay-shortcut.py`
- Sign: `shortcuts sign --mode anyone --input <out> --output site/apple-pay.shortcut`
- Live at `https://sortd.page/apple-pay.shortcut` — 22,243 bytes,
  sha256 `8e91834720c17f2b6b722c9dc8b0b1f5a91b38b6619f2f05a96a764fd1c79b99`

Also added: a 5-page picture guide for the setup, a **Send a Test Tap** button
(proves Sortd's half only — it works even with no shortcut installed, and the
copy says so), and a three-state connected status so a configured user stops
seeing "Waiting for your first tap".

**Not fixable by us:** Apple's Wallet trigger waits for the issuer to push
transaction details and silently gives up on timeout — radars FB14035016 /
FB16379100, broken since iOS 18. Unattended terminals (vending machines,
transit, parking) are the worst case. FinanceKit is US/UK only, so there is no
alternative for AU/SG.

### Polish — six passes, measured not guessed

| What | Before | After |
|---|---|---|
| `Color.down` as text | 3.66:1 — **failed WCAG AA** | 5.83:1 |
| `Color.up` as text | 3.09:1 — **failed** | 5.03:1 |
| Setup buttons | 62.7pt | 51pt |
| Restore Purchases / Terms / Privacy | ~16pt | 44pt |

- VoiceOver read "S$25.00" as "S, dollars twenty-five" → added `Money.spoken()`
  and switched every label that speaks an amount.
- Home's spending chart announced three category names and nothing else. Now
  labelled, with individually navigable points.
- One `Font.money` — amounts had been split between SF Rounded and plain SF, so
  numbers changed shape between screens.
- Primary CTAs use `.glassProminent`. Apple's `PrimitiveButtonStyle` owns the
  press animation *and* Reduce Motion. **I first wrote a custom scale style and
  research corrected me — never stack a custom scale on a system glass style.**
- Activity search → `.searchable`; no results → `ContentUnavailableView.search`.
- Row → detail uses `matchedTransitionSource` + `navigationTransition(.zoom)`.
- Reduce Motion and `accessibilityPrefersCrossFadeTransitions` (26.4,
  availability-gated) honoured.
- Data loss stopped: the add sheet no longer bins typed input on swipe-away;
  number pads got a keyboard Done; "Not Recurring" got an undo; sample-data
  Clear got a confirmation.
- Pull-to-refresh was **completely silent** — ran the sync, threw the result
  away. Now reports what it found or that it failed.
- Import set `busy` true and false in one runloop turn, so the spinner never
  drew and a big statement looked like a freeze.
- Delete All Data and Replace Everything are **alerts**, not dialogs. A dialog
  anchored to a row renders as a narrow popover that wrapped the message into
  five ragged lines and hid Cancel.
- SE/Pro/Pro Max clipping: budget overflow, bank grid truncation, Insights row
  wrap, sheet detent clipping Remove, `FlowLayout` placing chips off-screen.

---

## Still to do

### 1. The abuse findings — on `main` as known-bug tests

`SpendTests/AbuseMoneyAgentTests.swift` and `AbuseDataAgentTests.swift` are on
`main`. Every test that fails is tagged `.knownBug` and skipped unless you ask:

```
scripts/test.sh --known-bugs
```

CI does not run them, so it stays green. **23 tagged tests fail.** (The run on 24 Sep
2026 found 30, one only on CI; one is fixed and Raj had the 7 disputed ones deleted.) Each
test's doc comment says what is wrong and where. Fixing one means removing its tag.

**Fixed:** `AmountParser.currency(in:)` matched markers as substrings
(MYRTLE → ringgit, CARMENS → ringgit, HOURS. → rupees). Markers must now
stand alone.

### 2. UI adversarial pass — ran on 24 Sep, findings not fixed

Full table in `docs/UIPass-2026-09-24.md`. iPhone SE, 18 Pro and 18 Pro Max on iOS 27;
default, dark, AX5 and Reduce Motion. Worst first:

- **P1** Paywall at AX5: the "Start Free Trial" footer covers the plan list, so only the
  default plan can be picked; the terms are cut off; Restore/Terms/Privacy break mid-word.
- **P2 (was "P1, P0 if confirmed")** Undo on the delete toast: `finding-verifier` read the
  code (`ActivityView.swift:103-158`). Taps cannot fall through a live toast. But the purchase
  is really deleted 6 s after the swipe, and the toast then fades for 0.35 s during which a
  visible "Undo" does nothing and the tap reaches the row below. Fix: longer window (8–10 s,
  like Mail), and commit only after the fade ends.
- **P2** Insights 1W/1M/3M chips wrap at normal size and are unreadable at AX5.
- **P2** Yen shows two decimals everywhere except the Home headline (`JP¥69,326.02`).
- **P2** The Settings gear sits over the search Cancel button.
- **P2** The monthly budget changed from JP¥185,295 to JP¥1,850,000 with no save; step unknown.
- **Not checked:** VoiceOver in the running app (the simulator's accessibility inspect was
  unavailable; labels were read from code, and `Money.spoken` gives "25.00 Australian dollars",
  not words), emoji input, tab switching during a real sync, import with a real file, About,
  Help, Cards & Appearance, Learned Categories.

### 3. No backup, no CloudKit

Local-only SwiftData: losing the phone loses every transaction. The biggest
structural gap and the clearest miss against HIG Agency.

### 4. Dynamic Type at AX5 — now looked at

`xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large` works on this
Xcode. The UI pass covered Home, Activity, Insights, add sheet, detail, paywall and the
onboarding budget step at AX5. The paywall is the one that breaks (above).

### 5. Smaller, all traceable to Apple docs

`navigationSubtitle` (0 uses), `SnippetIntent` on the Siri intents,
`UndoableIntent` on `LogWalletTapIntent`, `accessibilityChartDescriptor`,
`ViewThatFits` instead of `minimumScaleFactor` on money rows, concentric
corners, layered app icon in Icon Composer, widget accented-rendering check.

### 6. `SORTD_BETA` — done

Removed by the free-app overhaul, sub-spec 1 (`docs/specs/2026-09-25-free-app-overhaul-1-free.md`):
the whole app is free now, so there is no paywall left to give away. PR pending.

---

## The one thing only Raj can do

His vending-machine test used the **old** shortcut, before the fix. The fixed
file went live afterwards. Nobody has retested.

1. Sortd → Apple Pay step → **Get the Shortcut**
2. Choose **Replace**
3. Buy something small at a **staffed till** on a Visa — not a vending machine
4. Read Settings → Purchase Sources → Apple Pay Logging → **Last Tap Received**

That line decides whether the fix worked or whether it is Apple's timeout.

## Decisions still open

1. **UI pass finding 13** (the budget jumped to JP¥1,850,000 with no save): `finding-verifier`
   read every writer and found none that fires without a tap. Unreproduced; watch for it.
2. **Sentry** — decided: keep it, run it live. Lands in sub-spec 2b
   (`docs/specs/2026-09-25-free-app-overhaul-2b-crash-reports.md`), alongside the App
   Privacy label change to Crash Data, linked. Preflight still fails on it until then.
3. **Privacy policy** — whether it names a person or a business entity. Needs a
   lawyer.
4. **Old branches** — `forwarding-inbox`, `paywall-steps`, confetti, `LaunchOverlay`, and the
   folder rename in PR #8. Build, drop, or leave; see "Where things are".
5. **GitHub Pro** — the Student pack should give it; until it is active on the account there is
   no branch protection, only the pre-push hook.

---

## Traps — read before spending a day on these

- **Two research agents surveyed the wrong checkout** and reported a "P0
  FlatTabBar" that did not exist on the branch being worked on. Always verify an
  agent's survey against the actual worktree before acting.
- **Do not give several agents the same worktree.** Their test files land in the
  shared `SpendTests/`, folder-synced groups compile everything, and one
  half-written file breaks every build.
- **One simulator each**, or they fight over it.
- **StoreKit tests are simulator-dependent.** `ProStoreTests` fails on the
  iPhone 17 Pro / iOS 26.4 sim (`DCA7DC0C-…`) with `Product.products(for:)`
  returning nil, and passes on iPhone 18 Pro / iOS 27 (`E8041708-…`). It is not
  a code fault. **Use the iOS 27 simulator.**
- **Disk.** It filled to 98% and git began failing with `mmap failed`. Each
  `derivedDataPath` is ~3.5 GB — delete them when done.
- **Apple doc bugs.** The symbol is `.searchToolbarBehavior(.minimize)`, not
  `.minimized` (Apple's own sample is wrong), and it is
  `toolbarMinimizationBehavior(_:for:)`, not `toolbarMinimizeBehavior`.

## Things I got wrong

Listed so nobody repeats them:

- I said `preflight.sh` prints "Not ready" but exits 0. **False** — it exits 1.
  My test was reading `tail`'s exit status.
- I said the SE Activity list clipped rows under the tab bar. **False** — I
  scrolled to the end and it clears.
- I acted on an agent survey of the wrong checkout before verifying it.
- I first replaced `.buttonStyle(.plain)` with a hand-rolled scale on primary
  buttons; Apple's own styles already do it better.

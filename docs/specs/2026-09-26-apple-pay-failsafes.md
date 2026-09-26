# Apple Pay logging — failsafes (26 Sep 2026)

## Problem

The whole Apple Pay feature rides on one thing Sortd cannot see or control: a personal
Shortcuts automation the user builds by hand, sitting on top of Apple's own Wallet
triggers. When it works, `LogWalletTapIntent` → `LogPurchaseIntent` → `TransactionLogger.log`
runs quietly and the tap shows up. When it does not, today Sortd mostly says nothing at
all — no dialog, no note, no row. We know from the code (`ApplePayStatus`,
`BugHunt-2026-09-26.md` U1/U6/M2/S6), from Apple's own forums, and from Raj's own
experience with a new iOS 27 trigger, that several of the ways this breaks are silent by
design (Apple's side) or silent by accident (ours). Raj has asked to make logging work
every time, and — where it can't — to know when it didn't.

## What Sortd already does vs. what's missing

Already built (verified by reading the code):
- A $0 amount is never dropped: `LogPurchaseIntent.swift:94-133` saves a row with
  `note: "Apple Pay sent no amount (…). Tap to fix."` — the user sees a row to fix, not a
  silent skip.
- A pure test run (▶ in Shortcuts, no fields at all) is told apart from a real tap and
  never saved (`LogPurchaseIntent.swift:94-97`).
- `lastTapReceivedAt`/`lastTapKey` record every time Shortcuts reaches the app, real or ▶,
  so the status page can say "reached" before the first real purchase (`LogPurchaseIntent.swift:51-67`,
  `ApplePayStatus.swift:44-55`).
- A same-shop, no-amount tap within 2 minutes is folded into the earlier row, not
  duplicated (`LogPurchaseIntent.swift:102-113`).
- `openAppWhenRun = false` on both intents (`LogWalletTapIntent.swift:14`,
  `LogPurchaseIntent.swift:12`) — the right call: Apple's own forums show
  `openAppWhenRun = true` can interrupt a locked-phone run entirely (Source 6).
- `LogWalletTapIntent` already accepts a **free-text `transaction` parameter** as well as
  discrete Amount/Shop/Card fields (`LogWalletTapIntent.swift:16-30`), parsed by
  `WalletTapText.parse`. This turns out to be exactly the right carrier for the new
  iOS 27 Notification trigger (see below) — no intent-schema change needed for that part.

Missing (the gap this spec is about):
- If `TransactionLogger.log`'s `try context.save()` throws for any reason, that throw
  propagates all the way out of `perform()` (`LogPurchaseIntent.swift:29-35`,
  `LogWalletTapIntent.swift:39-46`) — Shortcuts sees a failed action, nothing is saved,
  nothing is queued, nothing tells the user later.
- If `SpendStore.container` itself can't open, it calls `fatalError` (`SpendStore.swift:41-45`)
  — the whole process dies rather than the intent failing gracefully. No queue exists to
  hold a tap for later.
- `WalletTapText.parse`'s fallback — "any text at all is a real tap, so never drop it"
  (`LogWalletTapIntent.swift:53-57`) — will save a lone card name as a merchant (known bug
  U6, `BugHunt-2026-09-26.md`), which looks like a real purchase, not a mis-wired automation.
- Nothing aggregates the "amount missing" / "needs a check" rows anywhere the user is
  likely to look; they sit one at a time in Activity.
- No local notification exists for "a tap arrived but nothing was saved."
- No nudge exists for "the automation was set up but nothing has arrived in weeks."
- The real functional test ("run the Shortcut now" through the actual automation, not the
  in-app ▶) was designed as Option B in `docs/specs/2026-09-25-apple-pay-page.md` and
  deliberately deferred, not built.
- No diagnostics beyond the raw "Last Tap Received" text already in `PurchaseSourcesSettingsView.swift`.
- **New, from iOS 27:** a second automation trigger exists (Notification) that covers
  online, in-app, Apple Watch and Mac Apple Pay purchases the existing Transaction trigger
  cannot see at all — Sortd's setup guide (`WalletSetupGuide.swift`) only covers the
  Transaction trigger today, so every non-NFC purchase stays invisible even on iOS 27.

## New in iOS 27: a second trigger, and why it changes the design

iOS 27's Shortcuts app adds a **Notification** automation trigger: pick an app (Wallet),
and the automation fires on every notification from it, not just NFC taps (Source 2, 8, 9).
For Wallet, the notification's **Title is the card name, Subtitle is the merchant, Body is
the amount** (Source 8's own worked example). iOS 27 also lets one Shortcut hold *several*
triggers at once (Source 2: "you can now stack multiple automations in the same shortcut"),
so a single "Log Apple Pay in Sortd" automation can react to **both** the Transaction
trigger (in-store NFC, works since iOS 17) **and** the Notification trigger (everything
else, iOS 27 only) — closing the "online/in-app/Watch/Mac purchases are invisible" gap
named in the existing timeout copy (`ApplePaySetupPanel.swift:149`).

**Design:** for iOS 27, the setup guide adds a second branch inside the same automation:
Notification (app: Wallet) → join Title, Subtitle and Body with newlines into one block of
text → pass that block into Sortd's existing free-text `transaction` parameter, exactly
like the by-hand Transaction route already does. `WalletTapText.parse` already handles
this shape correctly with no code change: the amount-shaped Body line is picked out first,
the card-shaped Title line is matched by `looksLikeCard`, and the Subtitle becomes the
merchant by elimination (`LogWalletTapIntent.swift:83-119`) — verified by tracing the
parser's own logic against the Title/Subtitle/Body order, not run on a device.

**But this is not free** — Raj's own report ("[the Notification trigger] doesn't work,
fields come back empty") matches a wider pattern: commenters on the r/shortcuts thread
Raj found report the Title/Subtitle/Body coming back blank, one saying it worked "about
40% of the time," on iOS 27 betas (relayed by the coordinator; **not independently
fetched** — this tool cannot reach reddit.com, see Source 1). Two things follow, both
folded into the failure-mode table below as #13 and #14:
- A blank Notification run is, under today's code, indistinguishable from a harmless ▶
  preview (both produce empty text), so it would currently be **dropped silently** —
  exactly the failure this whole spec exists to close, and worse than doing nothing if
  shipped as designed without a fix.
- When a purchase is a normal in-store NFC tap, **both** triggers fire for it — Transaction
  with real data, Notification possibly blank or possibly a second copy of the same real
  data. Today's `Deduper.match` only merges purchases with a matching `amount > 0`
  (`Deduper.swift:21`), so a blank companion tap would never merge into the good one and
  would show up as a spurious extra row.

## Failure modes and failsafes

| # | Cause | What the user sees today (code) | Failsafe | Size | Files |
|---|---|---|---|---|---|
| 1 | Automation is on "Ask Before Running", not "Run Immediately" — missed the banner once, or iOS reset it after an update (Source 10) | Nothing. Status stays wherever it last was; no dialog fires because the automation itself never ran | Copy: name "Ask Before Running" explicitly in the setup guide and the timeout note. Behaviour: a 14-day "no tap since setup" nudge (shared with #3) | S copy, M nudge | `ApplePaySetupPanel.swift`, `WalletSetupGuide.swift`, new `Spend/Services/ApplePayNudge.swift` |
| 2 | Wallet's Transaction trigger only fires for in-store NFC taps — not online Apple Pay, not Apple Watch, not Mac (Source 5, 8, 11) | Purchase never appears; invisible to Sortd, nothing to detect | Partly closed by the Notification-trigger addition above (iOS 27 only). On iOS 26, copy only: extend the timeout note beyond "vending machines, transport gates and parking" to say online/Watch/Mac purchases never trigger the Transaction route at all | S copy (iOS 26), see #13/#14 for iOS 27 | `ApplePaySetupPanel.swift` (`timeoutNote`) |
| 3 | Apple's own transaction-timeout bug (FB14035016, FB16379100): the bank posts late, the automation's wait expires, the run is dropped silently — reported worse on some card networks than others (Source 4, 12) | Same as #1 from Sortd's side: nothing | Same 14-day nudge; name this explicitly in "Learn more" copy so it doesn't read as "Sortd is broken" | S (shares #1's nudge) | `ApplePaySetupPanel.swift` |
| 4 | A late-posting tap (see #3) lands as a same-day duplicate once it finally arrives (known bug S6) | A second, duplicate purchase; weekend spending doubles | Already tracked outside this spec (`Spend/Services/Deduper.swift:16`, "traced, test written"). Flagged here only because it compounds #3 | (tracked elsewhere) | `Spend/Services/Deduper.swift` |
| 5 | Two automations exist on the same trigger (an old by-hand build plus the new ready-made one) | Two dialogs fire; the Deduper folds same-amount/same-card/near-time duplicates, but a garbage or no-amount run may not match and creates two rows | Copy only: the setup flow already says "Get It Again"/"Replace" (`ApplePaySetupPanel.swift:78`); make "Replace, don't add a second one" explicit in-page | S | `ApplePaySetupPanel.swift` |
| 6 | The app was force-quit by the user; **not verified** whether iOS still grants a background `openAppWhenRun = false` intent its usual run in that state | Unknown — no evidence either way in this codebase or in Sources | Rely on the 14-day nudge (#1) as a catch-all; add "last app launch" next to "last tap received" in diagnostics so a launch-correlated pattern is visible | S | `PurchaseSourcesSettingsView.swift` |
| 7 | Phone rebooted and never unlocked since; the very first Wallet tap lands before first unlock, when the store's file-protection class may not be accessible to a background-launched process — **not verified for App Intents specifically**, only the general iOS data-protection principle | Unknown; likely the write silently fails | Route through the same tap queue as #9 rather than SwiftData directly; low priority, rare, not reproduced | S | new `Spend/Services/TapQueue.swift` |
| 8 | `SpendStore.container` can't open (disk full, corrupt file, failed migration) — today this is `fatalError` (`SpendStore.swift:41-45`), or a save throws mid-write | Process dies, or the intent throws; Shortcuts shows a failed-action state (exact wording **not verified**); nothing saved, nothing retried, no note anywhere | Wrap the save path in `do/catch`. On failure, write the raw fields (merchant, amount text, card text, date) to an app-group store (`group.com.kameshraj.spend`, `WidgetSummary.swift:99`) instead of SwiftData, and always return a normal `.result(dialog:)` so Shortcuts never sees a failure. Replay the queue at the next successful launch through `TransactionLogger.log` like any other source | M | `SpendStore.swift`, `LogPurchaseIntent.swift`, `LogWalletTapIntent.swift`, new `TapQueue.swift`, `App/SpendApp.swift` (replay at launch) |
| 9 | A queued tap (#8) sits unsaved until the next launch, which may be days away | User has no idea anything went wrong | One local notification per queued item: "A tap didn't save — open Sortd to check", using the existing `Reminders.swift`/`UNUserNotificationCenter` pattern | S | `Reminders.swift` or `TapQueue.swift`, `NotificationRouter.swift` |
| 10 | Automation wired to the wrong variable: the whole Transaction as text into one field, only one of Amount/Card/Merchant supplied, or a bank/region that leaves a Wallet field blank (Source 7 shows this happens even to a correctly-written custom App Intent, on Apple's own account) | Already **not** a silent skip in the common case — but a lone card name is saved as if it were the merchant (known bug U6, `LogWalletTapIntent.swift:56`), which reads as a real purchase, not a warning | Tighten `WalletTapText.parse`'s fallback: text that only `looksLikeCard` is never accepted as a merchant. Keep the row (never drop a tap) but tag it distinctly ("needs a check — got a card, no shop or amount"). Aggregate all "needs a check" rows into one count/banner on the Apple Pay status page and Purchase Sources | M | `LogWalletTapIntent.swift`, `LogPurchaseIntent.swift`, `ApplePayStatus.swift`, `ApplePaySetupPanel.swift`, `PurchaseSourcesSettingsView.swift` |
| 11 | No honest way to prove the automation itself (not just the app) is wired right, before a real till visit | The old fake test (`TapTestButton`) was removed 25 Sep 2026 for lying; nothing replaced it | A real "Check the Shortcut" run: `shortcuts://x-callback-url/run-shortcut?name=Log%20Apple%20Pay%20in%20Sortd&input=text&text=<known payload>&x-success=…&x-error=…` (documented scheme; response payload **not verified**, per the 25 Sep spec's own note). Compare what came back against the known payload field by field and say exactly what's wrong. Tag with a distinct, excluded test merchant and delete once confirmed | L (device spike needed) | new `Spend/Services/ApplePayHealthCheck.swift`, `ApplePaySetupPanel.swift`, `LogPurchaseIntent.swift`, `App/SpendApp.swift` |
| 12 | No single place shows the state of the whole pipeline | Only the raw "Last Tap Received" text exists (`PurchaseSourcesSettingsView.swift`) | One diagnostics block: last app launch, last tap received, "needs a check" count, last health-check result | S | `PurchaseSourcesSettingsView.swift` |
| 13 | **iOS 27 Notification trigger fires with Title/Subtitle/Body all blank** — reported common on betas (Source 1, relayed, not independently verified), no reliability data found for the shipped release (Source 2, 3, 9 describe the feature but not its failure rate) | Under the design above, a blank Notification run produces empty text, which today's code reads as a harmless ▶ preview and drops entirely (`LogWalletTapIntent.swift:52-57`, `LogPurchaseIntent.swift:94-97`) — a real tap would vanish exactly like #1/#3, but caused by us, not Apple | The automation must mark a real Notification-trigger run as real even when its fields are blank — e.g. join Title/Subtitle/Body behind a fixed literal token the shortcut always writes (not something Apple provides), so an empty-fields real run still arrives as non-empty text and is saved as a "tap arrived, details missing" row instead of being read as a ▶ test. Show it on the status page like any other "needs a check" row (#10) | M (needs a device spike to see what a real blank Notification payload and a ▶ preview of the same automation actually look like) | `WalletSetupGuide.swift` (iOS 27 branch), `LogWalletTapIntent.swift`, `SpendTests` |
| 14 | **Both triggers fire for one in-store tap** (Transaction with real data, Notification blank or a second copy) once the iOS 27 addition ships | Deduper requires `new.amount > 0` to even attempt a merge (`Deduper.swift:21`), so a blank companion tap can never fold into the real one — it would show as a spurious extra "needs a check" row for a purchase that already logged correctly | A narrower merge rule, ahead of the general Deduper: a same-card, zero-amount, no-merchant tap arriving within ~5 minutes of an already-logged real tap on the same card is treated as the same purchase and dropped, not logged as its own row. No stable transaction id is known to exist to key this on instead (**not verified** either way — see Sources) | S/M | `Spend/Services/Deduper.swift` or `LogPurchaseIntent.handle` |

## Recommendation

Build in this order: (1) #8/#9 — throw-safety and the tap queue plus its notification,
because this is the only failure mode that currently loses data outright with zero trace;
(2) #10/#13/#14 together — stop a mis-wired or blank-fielded automation from either
looking like a real purchase or vanishing like a ▶ preview, and de-duplicate the two
triggers; (3) #1/#3 — the 14-day nudge and copy for the two Apple-side silent failures;
(4) #12 — the diagnostics line, almost free once #8/#10 exist; (5) #11 — the real health
check, only after a device spike. **Do not ship the iOS 27 Notification-trigger addition
to the setup guide until #13 and #14 are built and verified on a real iOS 27 device** —
adding a second trigger that can silently vanish or silently duplicate is a net loss for
the subset of users who take the extra step. Do #2 (iOS 26 copy)/#5/#6/#7 as copy-only
riders on the same PR, and leave #4 (S6) to its own already-tracked fix.

## Risks

- **Data loss, reduced not removed.** The queue (#8) only helps when the app *can* open
  later. A permanently corrupt store still loses queued taps with it.
- **False "needs a check" flags.** Tightening the card-only fallback (#10) could
  mis-classify an unusual but real merchant name that happens to contain a card word
  ("Visa Nails Salon"). Extend `WalletTapText`'s existing test suite to cover it.
- **The iOS 27 addition could make things worse, not better, if shipped too early** — see
  the ordering constraint in Recommendation above. This is the main new risk this pass adds.
- **Privacy.** The tap queue holds merchant text, amount text and card text in the app
  group before it's ever categorised — the same data `Transaction` already stores, just
  briefly outside SwiftData. No new data leaves the phone; no privacy-label change. This
  matches the "everything stays on the phone" line every comparable app's guide makes a
  point of stating (Source 5, 12, 13).
- **App Review.** No new capability, no new entitlement. The health check's URL scheme use
  is app-initiated, same class of thing `AppReviewNotes.md` already documents.
- **Migration.** No SwiftData model change in this spec — the tap queue and "needs a
  check" flag can live as a note/UserDefaults marker, not a new `Transaction` field. A
  later typed flag on `Transaction` needs its own `SchemaV2` and a `MigrationTests` case;
  out of scope here.

## Test plan

Swift Testing (`test-writer`, in-memory container):
- `perform()`/`handle()` never throws when `context.save()` throws (inject a failing
  context) — the queue receives the raw fields instead, and the dialog still reads success.
- A queued item replays through `TransactionLogger.log` at the next launch and becomes a
  normal `Transaction` with `source: .tap`; replay is idempotent (running it twice does not
  double-log).
- `WalletTapText.parse("Visa Debit ••4821")` (card-shaped text, no amount/merchant) →
  no merchant set, tagged "needs a check", not "Visa Debit ••4821" as a shop name.
- `WalletTapText.parse("Visa Nails Salon A$12")` → merchant is kept (a real shop name that
  contains a card word still counts, once an amount is present).
- Title/Subtitle/Body order ("Visa Debit" / "Seven Seeds" / "A$4.50") joined with newlines
  → parses to card "Visa Debit", merchant "Seven Seeds", amount 4.50 — the exact
  composition the iOS 27 design depends on.
- A real Notification-trigger run whose Title/Subtitle/Body are all blank, marked with the
  fixed literal token, is saved as "needs a check", not dropped as a ▶ preview.
- A zero-amount, no-merchant, same-card tap arriving 3 minutes after a real logged tap on
  that card is dropped, not logged as a second row; one arriving after 10 minutes is kept.
- "Needs a check" count on `ApplePayStatus`/a status helper counts $0-amount and
  card-only-fallback rows, excludes `legacyTestMerchant` and DemoData rows.
- The 14-day nudge fires once when `lastTapReceivedAt` (or `.tapLogged`) is more than 14
  days old and Apple Pay setup was completed; does not fire before setup, does not fire twice.
- Health-check payload round-trip: a known merchant/amount/card string in → the same three
  fields out, tagged with a new excluded test-merchant constant, excluded from
  `ApplePayStatus.realTaps` and `Activation.detect` exactly like `legacyTestMerchant` today.
- Existing `ActivationTests`, `AnalyticsTests`, `SuggestionsTests`, `BugHunt*Tests` still pass.

`ui-driver`:
- Purchase Sources shows the new diagnostics block (last launch, last tap, needs-a-check
  count, last health-check result) at SE, Pro Max, AX5, dark mode.
- A "needs a check" banner appears when the count is non-zero and links to the flagged rows.
- The health-check button shows a specific, per-field result, not just pass/fail.
- On iOS 27, the setup guide shows the second (Notification) branch only after #13/#14 ship.
- VoiceOver reads the diagnostics block and the nudge notification text correctly.

Device only (Raj), can't be done in a simulator:
- A real Wallet tap actually reaching a fresh install through the ready-made shortcut.
- What a real, blank-fielded iOS 27 Notification-trigger run actually contains, versus a
  ▶ preview of the same automation — needed to design #13 correctly; this is presently a
  guess based on relayed forum reports, not a device observation.
- The health check's `x-callback-url` round trip (return payload, any confirmation prompt).
- Whether `openAppWhenRun = false` still runs promptly right after a force-quit.
- Whether Low Power Mode delays or drops the run.
- The before-first-unlock edge case (#7) — needs a reboot timed right before a tap.

## Ten-minute real-phone test plan

1. **Before leaving (2 min).** Settings › Purchase Sources › Apple Pay Logging. Note the
   current "Last Tap Received" time. Run "Check the Shortcut" (once built, #11) and confirm
   it reports every field matched, not just "OK".
2. **Force-quit Sortd** (swipe it away). Turn on Low Power Mode. (30 s)
3. **Tap to pay** something small (A$2–5) on a Visa at a staffed till, not a vending machine
   or gate. (2 min)
4. **Re-open Sortd immediately**, don't wait. Check: does the purchase already show in
   Activity, right amount and shop? Does the status card say "Last tap logged · today
   HH:MM"? (1 min)
5. **If it hasn't shown within ~60 s, wait** — Apple's own trigger can take minutes when the
   bank posts late (FB14035016). Check again after 2 more minutes. (2 min)
6. **If a second card is available (ideally a Mastercard),** repeat the tap — forum reports
   say some card networks see the timeout bug more than others. (2 min, optional)
7. **If on iOS 27 with the Notification branch installed**, check whether *two* rows
   appeared for the one tap, and whether either has blank fields — this is the exact thing
   #13/#14 are meant to catch. (30 s)
8. **Turn Low Power Mode back off.** Check Settings › Notifications › Wallet ›
   "Summarize Notifications" is off. (30 s)
9. **Check for a "needs a check" banner** — there should be none if the tap parsed
   cleanly; if one shows, open it and read what it says is missing. (30 s)

## Sortd's guide vs. three other setup guides

Read for comparison, all third-party, none Apple's own:

- **Balance Trackr** (Source 13): a static web page, Transaction trigger only, explicit
  step order, and it warns not to tap ▶ ("do not tap the Play button… requires a restart").
  Sortd deliberately does the opposite — ▶ is a supported, harmless connectivity check
  that sets `ApplePayStatus.shortcutReached` (`ApplePayStatus.swift:9-13`) — a considered
  difference worth keeping, not a thing to copy. It also requires the card name to "match
  exactly" a name typed in its own app; Sortd avoids this by fuzzy-matching card names
  itself (`Banks.swift:109`, `matchOrCreate`) instead of demanding an exact string, which
  is more forgiving of what Wallet actually sends.
- **CashJot** (Source 12): more specific written warnings than Sortd's current copy —
  names delayed/suppressing issuers, transit-gantry batching, and "a few institutions
  don't dispatch local payload notifications at all," where Sortd's own timeout note only
  says "vending machines, transport gates and parking." Worth tightening Sortd's wording
  to match this level of specificity. Its numeric claims (issuers post in "1–2 seconds to
  a minute," a "90-second" dedupe window, Date/Currency Code available under "Show More")
  are **not verified** against Apple's own (field-free) documentation and read as
  marketing-level precision from a competitor, not to be copied as fact.
- **WalletPal** (Source 8): the only guide found that documents the iOS 27 Notification
  trigger for Wallet at all, with the Title/Subtitle/Body → Card/Merchant/Amount mapping
  this spec's design depends on. It gives **no warning** about empty fields or reliability
  — directly at odds with the Reddit reports relayed by the coordinator (Source 1). This
  disagreement (vendor guide silent on a problem end users report) is exactly why #13
  needs a device spike before shipping, not a reason to dismiss the Reddit reports.

## Open questions

1. Should the 14-day nudge repeat (every 14 days with no tap) or fire once and stay quiet?
2. Is holding merchant/amount/card text in the app-group tap queue (outside SwiftData,
   briefly) an acceptable trade-off against losing the tap outright if the phone is lost
   before Sortd next opens?
3. Build the real "Check the Shortcut" health check now (device spike needed) or ship the
   throw-safety/queue/notification work first and add the health check in a second pass?
4. Should "needs a check" become a real `Transaction` field (needs `SchemaV2` and a
   migration test) instead of a note/marker convention, once real-use volume is known?
5. Does Raj want the iOS 27 Notification-trigger addition at all in the near term, given
   it needs its own device spike and both #13 and #14 built first — or should Sortd stay
   Transaction-only until the Notification trigger's real-world reliability is confirmed
   independently of one relayed Reddit thread?

## Not verified

- Exact Shortcuts UI/error text when Sortd's intent throws mid-run — not reproduced on
  device, only reasoned from the code path.
- Whether an `openAppWhenRun = false` intent is still granted its run promptly right after
  the user force-quits the app — no documentation found either way.
- Whether the app-group container's default file-protection class actually blocks a
  background App Intent write before first unlock post-reboot — sourced from general iOS
  data-protection principles, not an App-Intents-specific test.
- The `run-shortcut` x-callback-url's `result` payload on a return trip from Sortd's own
  intent — flagged not verified in the 25 Sep spec already; still not verified here.
- Whether Apple's Wallet Transaction magic variable exposes a stable transaction
  identifier, or Date/Currency Code under "Show More" as CashJot claims — Apple's own
  guide page lists no fields at all (Source 3); third-party pages disagree on how much
  exists (Source 4, 7, 12).
- The Reddit thread's exact wording and vote counts — this tool cannot fetch reddit.com;
  the ~40%-reliability and "empty fields" claims are relayed by the coordinator from Raj,
  corroborated only indirectly (WalletPal's own guide for the same trigger gives no such
  warning, which is itself informative, see the guide comparison above).
- Whether the iOS 27 Notification trigger's reliability improved between the beta Raj/
  Reddit describe and the shipped release — no review (MacRumors, 9to5Mac, MacStories)
  found that measures this; all describe the feature's existence, none its failure rate.
- The Mastercard-vs-Visa timeout correlation (Source 4) — sourced from a single developer
  forum post, not confirmed by Apple or reproduced by us.
- No relevant GitHub issue or Stack Overflow question tying AppIntents specifically to
  Shortcuts-automation timeouts was found; the substantive reports are all on Apple's own
  developer forums (Sources 4, 6, 7, 14, 15).

## Rough size

Throw-safety + tap queue + notification (#8/#9): ~1.5–2 days. Needs-a-check tagging,
blank-Notification handling and the same-card dedupe rule (#10/#13/#14): ~2 days,
including the device spike for #13. 14-day nudge + copy (#1/#2/#3/#5/#6/#7): ~1 day.
Diagnostics line (#12): ~0.25 day. Real health check (#11): ~1.5–2 days including its own
device spike. Total, excluding S6 (already tracked elsewhere): roughly 6.5–7.5 days if all
of it ships; recommend the phased order above, and hold the iOS 27 Notification-trigger
addition back until its own two rows are done and verified.

## Paths read

`Spend/Intents/LogWalletTapIntent.swift`, `Spend/Intents/LogPurchaseIntent.swift`,
`Spend/Services/ApplePayStatus.swift`, `Spend/Views/Components/ApplePaySetupPanel.swift`,
`Spend/Views/WalletSetupGuide.swift`, `Spend/Services/SpendStore.swift`,
`Spend/Services/Activation.swift`, `Spend/Services/Reminders.swift`,
`Spend/Services/WidgetSummary.swift` (app group id), `Spend/Services/Deduper.swift`,
`Spend/Models/Banks.swift` (`matchOrCreate`), `CLAUDE.md`, `HANDOVER.md`,
`docs/AgentPipeline.md`, `docs/specs/2026-09-25-apple-pay-page.md`,
`docs/AppReviewNotes.md`, `docs/BugHunt-2026-09-26.md` — all read from
`/Users/kameshraj/Developer/Sortd/.claude/worktrees/spec-applepay-failsafes`. (Note: this
worktree's `CLAUDE.md` was reported as updated on disk mid-task — backup is now a real
iCloud record, not a known gap. Not relevant to this spec's design; noted for the record.)

## Sources

1. r/shortcuts, "Automatically log your wallet transactions to 3rd party apps using the
   new notifications automation" (reddit.com/r/shortcuts/comments/1u1fuem), relayed by the
   coordinator on Raj's behalf, **not independently fetched — this tool cannot reach
   reddit.com**. Adds: the Title/Subtitle/Body-blank problem and a "~40% of the time"
   estimate on iOS 27 betas; one comment asks whether the trigger ships at all in the final
   release. Treated as anecdotal until a device spike confirms or refutes it.
2. MacRumors, [iOS 27 Makes the Shortcuts App Much Less Intimidating](https://www.macrumors.com/guide/ios-27-shortcuts/),
   read 26 Sep 2026. Adds: confirms a "When a notification is received" trigger exists in
   shipped iOS 27; no field-level or reliability detail.
3. Apple Support, [Event triggers in Shortcuts on iPhone or iPad](https://support.apple.com/guide/shortcuts/event-triggers-apd932ff833f/ios),
   read 26 Sep 2026. Adds: Apple's own, minimal description of the Notification trigger
   ("specify the app," "filter the Message, Subtitle, or Title") — no field names for
   Transaction at all, contradicting third-party pages that list specific fields (Source 4, 7, 12).
4. Apple Support, [Transaction triggers in Shortcuts on iPhone or iPad](https://support.apple.com/guide/shortcuts/transaction-trigger-apd65c67538a/ios),
   read 26 Sep 2026. Adds: version tabs for iOS 17/18/26/27 with no stated differences;
   "When I tap: select a card" is the only option documented; no Run
   Immediately/Ask Before Running wording on this page itself.
5. Apple Developer Forums, [Shortcuts Automation Trigger Transaction Timeouts](https://developer.apple.com/forums/thread/765516)
   (FB14035016, FB16379100), read 26 Sep 2026. Adds: the timeout mechanism itself, worse on
   some Mastercard-linked cards than Visa (single-source, not verified), fires even on a
   declined transaction, workaround of disabling "Summarize Notifications" for Wallet.
6. Apple Developer Forums, [Appintent: openAppWhenRun breaks shortcut when phone is locked](https://developer.apple.com/forums/thread/732466),
   read 26 Sep 2026. Adds: confirms `openAppWhenRun = true` can interrupt a locked-phone
   run with no result dialog — supports Sortd's existing `openAppWhenRun = false` choice.
7. Apple Developer Forums, [Transaction Shortcuts + AppIntent is flaky occasionally](https://developer.apple.com/forums/thread/797233)
   (already cited in `LogPurchaseIntent.swift:80`), read 26 Sep 2026. Adds: a custom App
   Intent can receive an empty merchant/zero amount even when a built-in Shortcuts action
   passes the same data reliably; Apple DTS called it Shortcuts-side, not an App Intents
   bug, with no fix in the thread.
8. WalletPal, [How to trigger shortcuts when I get a notification](https://walletpalapp.github.io/apple-shortcuts-notification-trigger.html),
   read 26 Sep 2026. Adds: the concrete Title→Card, Subtitle→Merchant, Body→Amount mapping
   this spec's design is built on; gives no warning about empty fields, which disagrees
   with Source 1 (see the guide comparison above).
9. MacStories, [iOS and iPadOS 27: The MacStories Review, page 13](https://www.macstories.net/stories/ios-and-ipados-27-review/13/),
   read 26 Sep 2026. Adds: confirms a dedicated Notification magic variable exposing body
   text, "time-sensitive nature," and date; no reliability discussion.
10. Finny, [Why iOS Shortcuts Automations Are Flaky (and What to Do About It)](https://getfinny.app/blog/ios-shortcuts-automations-flaky-fix),
    read 26 Sep 2026. Adds: Ask Before Running silently drops a missed-banner run; Low
    Power Mode delays/skips background automations; Focus modes silence the result
    notification even when the automation ran.
11. Splitsies, [Capture Apple Pay payments automatically with a Shortcut](https://splitsies.dev/articles/2026-06-27-capture-payments-shortcut),
    read 26 Sep 2026. Adds: names Currency Amount/Name/Currency Code as the fields to map;
    warns that dragging the whole Transaction object in (instead of its properties) causes
    conversion errors; states the trigger is Apple Pay/Wallet only, not physical-card taps
    at a terminal without Apple Pay.
12. CashJot, [Apple Pay expense tracking](https://www.cashjot.com/blog/apple-pay-expense-tracking),
    read 26 Sep 2026. Adds: the most specific written failure-mode list of any guide read
    (delayed/suppressing issuers, transit-gantry batching, unsupported institutions); its
    numeric claims (Date/Currency Code under "Show More," a 90-second dedupe, 1–2 sec to
    1 min issuer delay) are **not verified** against Apple's own field-free documentation
    (Source 4).
13. Balance Trackr, [Siri Shortcuts Setup](https://balancetrackr.com/SiriShortcutsSetup/en.html),
    read 26 Sep 2026. Adds: warns explicitly against tapping ▶ ("requires a restart"),
    directly opposite Sortd's own design where ▶ is a supported connectivity check
    (`ApplePayStatus.shortcutReached`); requires an exact card-name string match, which
    Sortd avoids via fuzzy matching (`Banks.swift:109`).
14. Apple Developer Forums, [Transactions automations don't seem to work](https://developer.apple.com/forums/thread/773745),
    read 26 Sep 2026. Adds: a second, independent report of the same timeout bug as
    Source 5, reproduced by a different user after trying reinstall/restart; no Apple reply.
15. Apple Developer Forums, [Missing "add transaction" shortcut](https://developer.apple.com/forums/thread/767596),
    read 26 Sep 2026, found alongside Source 14 in the same search; **not fetched in
    detail** — surfaced by title only, flagged here for completeness rather than as a used
    source.
16. Graham Haley, [Apple Pay automation](https://grahamhaley.co.uk/2024/11/19/apple-pay-automation/),
    read 25 Sep 2026 (carried over from the prior spec's research). Adds: Card/Pass,
    Merchant, Amount and current Date as usable Transaction fields; "took about 8
    purchases" of trial and error to wire correctly; the ▶ test carries no real data.
17. MoneyCoach, [How To Import Apple Pay / Wallet Transactions](https://moneycoach.ai/guides/how-to-import-apple-pay-wallet-transactions-to-moneycoach)
    and [Troubleshooting Common Issues with Shortcut Automations](https://moneycoach.ai/blog/troubleshooting-common-issues-with-shortcut-automations-for-apple-pay-transaction-import),
    read 26 Sep 2026. Adds: same Run Immediately/Notify-off setup shape as Sortd's; its
    troubleshooting page covers only wrong amount format and wrong field mapping, nothing
    about duplicates, notifications, or iOS-update breakage — a narrower set of failure
    modes than this spec covers.
18. `docs/specs/2026-09-25-apple-pay-page.md` (this worktree). Adds: the prior decision to
    defer a real "check it works" health check (its Option B) pending a device spike — the
    spike this doc's #11 and #13 still both need.


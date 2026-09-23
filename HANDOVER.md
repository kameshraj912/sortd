# Sortd — handover

Last updated 24 September 2026. Written for whoever picks this up next.
Everything below was verified, not assumed — where I could not verify
something, it says so.

## Where things are

| | |
|---|---|
| Repo | `/Users/kameshraj/Developer/Sortd` (moved here from `~/Documents/Spend`) |
| Branch | `main` @ `829b74a` — **pushed**, nothing outstanding |
| Tests | **369 passing** |

Branches still holding work:

- **`abuse-findings`** — 1,191 lines of adversarial tests. **21 fail.** Deliberately
  not merged so CI stays green. They document real bugs; see below.
- **`ux-refresh`** — reports "14 commits not in main". **Ignore that.** A rebase
  during the push gave those commits new SHAs; the content is on `main` and I
  verified it file by file.
- **`beta-prep`** — fully caught up with `main`, nothing unique.

---

## What got done

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

### 1. The 21 abuse findings — on `abuse-findings`, none fixed

```
git checkout abuse-findings
xcodebuild test -scheme Spend -destination 'id=E8041708-8F0E-4714-9738-B9AF194C5B61'
```

**Confirmed real** (`Spend/Services/Parsing.swift:30-36`): `AmountParser.currency(in:)`
matches its markers as **substrings, not words**.

| Merchant | Contains | Booked as |
|---|---|---|
| **MYR**TLE CAFE 8.00 | `MYR` | Malaysian ringgit |
| CA**RM**ENS 12.00 | `RM` | Malaysian ringgit |
| HOU**RS.** 12.00 | `RS.` | Indian rupees |

Wrong currency, then run through FX. Needs word-boundary matching. **Fix this
one regardless of what you do with the rest.**

**The other 20 are untriaged** — some may assert behaviour nobody wanted. Check
each before "fixing":

*Money* — `isNegative` only checks the start of the string, so `A$-4.50` is not
seen as a refund; `12.345` parses as 12,345; a 16-digit card number parses as an
amount; `2 x A$4.50` takes the 2; JPY/THB/CHF/PHP/CNY currency dropped;
zero-decimal currencies shown with cents.

*Data* — a Gmail receipt merging into a purchase pending delete is lost forever;
duplicate ids in a backup survive restore and **double the total**; restoring the
same backup twice adds everything again; a negative amount in a backup takes a
month below zero; re-importing a statement adds it again; rows with no date are
dropped; absurd dates import; two payments at one shop collapse into one; a
recharge after a refund is not counted.

### 2. UI adversarial pass — never ran

Three agents were launched; Claude crashed and killed them. Two left the test
files above. The third — drive the simulator and break the UI by hand —
produced nothing.

### 3. No backup, no CloudKit

Local-only SwiftData: losing the phone loses every transaction. The biggest
structural gap and the clearest miss against HIG Agency.

### 4. Dynamic Type at AX5 — never verified visually

`simctl` has no content-size option; it needs the Settings app driven inside the
simulator. Issues were found by reading code. **Nobody has looked at the screens.**

### 5. Smaller, all traceable to Apple docs

`navigationSubtitle` (0 uses), `SnippetIntent` on the Siri intents,
`UndoableIntent` on `LogWalletTapIntent`, `accessibilityChartDescriptor`,
`ViewThatFits` instead of `minimumScaleFactor` on money rows, concentric
corners, layered app icon in Icon Composer, widget accented-rendering check.

### 6. `SORTD_BETA` still on in Release

Right for TestFlight, fatal for the App Store — App Review would never see the
paywall. `scripts/preflight.sh --appstore` correctly exits 1 on it.

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

1. **Abuse findings** — fix the 21 then merge, or merge now and accept a red CI
   as a visible to-do list. Asked twice, not answered.
2. **Sentry** — still linked. Either remove the package and
   `CrashReporting.swift`, or change the App Privacy label to Crash Data (not
   linked). Preflight fails on it today.
3. **Privacy policy** — whether it names a person or a business entity. Needs a
   lawyer.

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

# Overhaul 8: instant results, with undo (25 Sep 2026)

Part of `2026-09-25-free-app-overhaul-overview.md`.

## Problem

Raj: "Add optimistic UI." Most Sortd actions are local SwiftData writes, and they are already instant. The real gaps are:
- actions whose result is hidden or late;
- actions that wait on the network (Gmail, exchange rates);
- the delete undo, which lies for 0.35 s (`docs/UIPass-2026-09-24.md`, P2).

## Candidates, ranked by what the user notices

| # | Action | Today | Instant version |
|---|---|---|---|
| 1 | Delete from Activity | Deleted 6 s after the swipe. A visible "Undo" does nothing during the 0.35 s fade (`ActivityView.swift:103-158`, `PendingDeletes.swift`) | Row gone at once. Undo lasts 8 s. The real delete happens only after the toast has fully gone |
| 2 | Change a category that moves other purchases at the shop | Moves them silently (`TransactionLogger.recategorise`) | Toast: "Moved 12 others at Coles · Undo". Undo restores each category and the old rule |
| 3 | Connect Gmail | Builder to check `GmailViews.swift` | Account row appears the moment Google says yes, with live `SyncStatus` ("Reading receipts…"). A failed first sync keeps the row and shows Retry |
| 4 | Add in another currency | Saved at once; `FXService.backfill` runs after (`AddTransactionView.swift:385-392`) | Row shows the original amount with "converting". Home total says "+1 converting" instead of silently leaving it out (check `Transaction.audValue`) |
| 5 | Refresh (pull, exchange rates) | `RefreshNote` reports the result | Old numbers stay, marked stale. New ones animate in with `numericText` |
| 6 | Budget save | Local, instant | Nothing to do (haptic comes with sub-spec 5) |

**From the references (`docs/ux-research/07`):**
- **Context suggestions in the add sheet (Endel).** Time of day and recent shops suggest a merchant and category before typing. Built from local history only.
- **Proactive budget nudge (Flighty).** "On track to pass your budget by the 22nd." On Home, and at most one local notification a month (research 03 #7 caps pushes).
- **Outcomes, not only totals, in Insights (One Sec).** "12% less than last month by now." Insights is free after sub-spec 1.
- **Live Activity** for Gmail sync and the monthly budget: too big for here (new target). It gets its own later spec.

## Options

- **A. Fix 1–5, add suggestions, the nudge and outcome lines (recommended).** 4 d.
- **B. A general pending-changes layer with rollback.** 6 d+. Overkill: the store is local and the writes do not fail.
- **C. Only fix delete (1).** 0.5 d. Leaves the rest.

## Recommendation

A, in the order of the table. Start with delete: it is the only data-loss risk here. Every write still goes through `TransactionLogger` (add) or its existing helpers (`recategorise`). Undo must reverse them the same way, never by inserting a `Transaction` directly.

## Files

- `Spend/Views/ActivityView.swift`, `Spend/Services/PendingDeletes.swift`.
- `Spend/Services/SpendStore.swift`: `recategorise` returns what it changed, for undo.
- `Spend/Views/TransactionDetailView.swift`.
- `Spend/Views/GmailViews.swift`, `Spend/Services/SyncStatus.swift`, `Spend/Views/Components/SyncStatusViews.swift`.
- `Spend/Views/AddTransactionView.swift`, `Spend/Models/Transaction.swift` (read only: `audValue`, `needsRate`).
- New `Spend/Services/Suggestions.swift`.
- `Spend/Views/HomeView.swift`, `Spend/Services/Reminders.swift`, `Spend/Views/InsightsView.swift`, `Spend/Views/HomeInsights.swift`.

## Test plan

- **Delete:**
  - swipe → hidden from the list at once;
  - the store still holds the row until 8 s have passed and the toast has gone;
  - undo at 7.9 s restores it;
  - a tap during the fade does not reach the row below.
- **Recategorise with others:**
  - the change record lists each moved id and its old category;
  - undo restores every one;
  - undo restores the old `MerchantRule`, or removes the new one.
- **Gmail:** fake sign-in succeeds and the first sync fails → the account stays listed with a Retry state; nothing is lost.
- **Foreign currency:** add 25 SGD with no rate → row shows "S$25.00", `needsRate == true`, and the Home pending count is 1. When the rate arrives → count 0.
- **Suggestions:**
  - history of 5 weekday 8 am coffees → at 8:10 on a Tuesday, the first suggestion is that shop;
  - empty history → none;
  - a merchant seen only once → not suggested.
- **Pace:**
  - 600 of 1,000 spent by day 10 of a 30-day month → the projection passes on day 17;
  - on pace → nil; no budget → nil;
  - nudge at most once a month.
- **Outcome:**
  - 880 this month vs 1,000 at the same day last month → "12% less than last month by now";
  - last month 0 → no line.
- `ui-driver`:
  - undo toast at AX5;
  - VoiceOver announces "Deleted. Undo";
  - pending-conversion label;
  - suggestion chips at AX5.
- Device only: Gmail connect on a real account.

## Gate

- Raj approves the ranking.
- Known-bug count does not rise.
- UI pass on the undo toast.

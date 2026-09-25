# Overhaul 7: in-app tips (25 Sep 2026)

Part of `2026-09-25-free-app-overhaul-overview.md`.

## Problem

Raj: "In-app onboarding, steps once inside the app to explain the buttons." The app has no TipKit and no coach marks (`docs/ux-research/01` §4, still true: grep finds no `TipKit`). NN/g found that up-front tutorial decks did not improve task success (research 02). So tips should appear at the moment a feature matters, not as a tour.

## Options

| | A. TipKit, event-driven, one at a time (recommended) | B. First-run coach-mark overlay tour | C. Empty-state copy only |
|---|---|---|---|
| System component | yes (`Tip`, `TipView`, `.popoverTip`, `Tips.configure`) | custom | yes |
| Work | 2 d | 3 d | 0.5 d |
| Risk | little; TipKit handles "shown once" and invalidation | ignored and skipped (NN/g) | too quiet |

## Recommendation

A.
- Call `Tips.configure` at launch in `SpendApp` with a display frequency limit.
- Show at most one tip on screen. Use `TipGroup` (ordered) where tips share a screen. **Not verified:** `TipGroup` availability and API shape on iOS 26.
- Show no tips during setup, and none before the first-launch session ends.
- Mark each tip invalid as soon as the user does the thing.

First step: the eligibility rules as pure functions, with tests.

| Tip | Where | Shows when | Stops when |
|---|---|---|---|
| "Add cash or anything Apple Pay missed" | + (add) | Home seen twice, no manual purchase yet | a purchase is added by hand |
| "Log Apple Pay by itself" | Finish Setup card, Apple Pay row | setup done, Shortcut never reached the app | `shortcutHasReachedApp` |
| "Swipe left to change a category or delete" | first Activity row | 3rd Activity visit, 5+ purchases | a swipe action is used |
| "Search by shop, category or note" | Search tab | 20+ purchases | a search is run |
| "See this month next to last" | Insights | first visit with 7+ days of data | the period chips are used |
| "Tap the month to look back" | Home month menu | second calendar month of data | the month is changed |

The copy is one plain line each, with no "Pro", and a VoiceOver-readable tip. Analytics records `tip_shown` and `tip_used` (sub-spec 2).

## Files

- New `Spend/Views/Components/Tips.swift`.
- `Spend/App/SpendApp.swift` (configure).
- `Spend/Views/HomeView.swift`, `Spend/Views/ActivityView.swift`, `Spend/Views/SearchView.swift`, `Spend/Views/InsightsView.swift`, `Spend/Views/Home/FinishSetupCard.swift`.
- `Spend/Views/DataControlsView.swift`: Delete All Data resets tips.
- Settings › Help: "Show tips again".

## Test plan

- `TipRules.addTip(homeVisits: 2, manualCount: 0) == true`; with `manualCount: 1` → false.
- `swipeTip(visits: 3, purchases: 5, swipeUsed: false) == true`; `visits: 2` → false; `swipeUsed: true` → false.
- `searchTip(purchases: 19) == false`, `20` → true.
- `applePayTip(setupDone: true, reached: false) == true`; `reached: true` → false.
- While setup is showing: every rule returns false.
- "Show tips again" → `Tips.resetDatastore()` is called. How to test TipKit's store in unit tests is **not verified**. Fall back to testing through a wrapper.
- `ui-driver`:
  - only one tip on screen at a time on every tab;
  - tips at AX5 do not cover the tab bar;
  - VoiceOver reads the tip and its close button;
  - dark mode.
- Device only: none.

## Gate

- Raj approves the tip list and its copy.
- UI pass confirms one tip at a time.

## Sources

- [TipKit docs](https://developer.apple.com/documentation/tipkit), read 25 Sep 2026. Only the type names were visible; OS versions **not verified**.
- NN/g tutorials, via research 02.

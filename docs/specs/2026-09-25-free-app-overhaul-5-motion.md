# Overhaul 5: haptics and oriented transitions (25 Sep 2026)

Part of `2026-09-25-free-app-overhaul-overview.md`.

## Problem

Raj: "Add haptics for the app" and "oriented transitions".

**Haptics today.** There are 20 `sensoryFeedback` calls in 14 files, each picked on its own:
- Delete uses `.impact(weight: .medium)` (`ActivityView.swift:107`).
- A refused key uses `.impact(weight: .light)` (`AddTransactionView.swift:281`).
- Nothing plays on undo, Gmail connected, or a failed save outside `RefreshNote`.
- `.warning` is never used.

**Transitions today.**
- Setup slides in the direction of travel, and cross-fades under Reduce Motion or Prefer Cross-Fade (`OnboardingView.swift:70-117`).
- Activity rows zoom into their detail (`ActivityView.swift:246,253`).
- Home's card carousel (`HomeView.swift:374`) and Recent rows (`:475`) use a plain push.
- Changing month on Home just swaps the numbers.

## Reading of "oriented transitions" (a guess)

Motion follows direction: forward goes in, back comes out, next month comes from the right, and a detail grows from the row you tapped. Other reading: landscape support. I did not design for that (overview question 8).

## Options

| | A. One feedback map + extend what exists (recommended) | B. Per-screen tweaks | C. Custom Core Haptics patterns |
|---|---|---|---|
| Work | 3 d | 1 d | 5 d+ |
| Consistency | one table, testable | drifts again | high, but custom |
| Risk | touches 14 files | low | fights the system; HIG prefers system patterns (research 03, source 31) |

## Recommendation

A.

**1. Feedback map.** Add `Feedback` in `Views/Components/Feedback.swift`: a pure enum mapped to `SensoryFeedback`:

| Event | Feedback |
|---|---|
| select | `.selection` |
| confirm / save | `.success` |
| fail | `.error` |
| blocked input / over limit | `.warning` |
| delete | `.impact(weight: .medium)` |
| undo | `.impact(weight: .light)` |
| aha | `.success`, once |

Add a `.feedback(_:trigger:)` modifier and replace the 20 calls. Never on scroll. Chart scrub and carousel paging count as selection. No custom patterns. The system handles the user's System Haptics setting for `sensoryFeedback` (**not verified**).

**2. Transitions.**
- Zoom from Home Recent rows and from the card carousel into their details (the same `matchedTransitionSource` + `navigationTransition(.zoom)` as Activity).
- Home month change: `.push(from: .trailing/.leading)` on the totals, by direction, and `.opacity` under Reduce Motion or Prefer Cross-Fade. Reuse setup's `crossFade` logic. Move it to a shared helper, keeping its `#if compiler(>=6.4)` guard.
- Tab switches stay the system's (instant). HIG does not ask for animated tab changes.

**3. Day pages (TeuxDeux reference):** Activity as one day per page, swiping between days. Shipped behind a DEBUG flag until the UI pass (pipeline rule 3); the default since 25 Sep 2026, with the old list left in for the DEBUG escape `SPEND_ACTIVITY_LIST=1`. The header says where the day sits ("Yesterday · 2 of 14") and one swipe moves one day.

First step: the `Feedback` map and its tests.

## Files

- New `Spend/Views/Components/Feedback.swift`.
- Every file with `sensoryFeedback`:
  - `App/SpendApp.swift`
  - `Views/OnboardingView.swift`, `Views/Onboarding/SetupPages.swift`
  - `Views/HomeView.swift`, `Views/ActivityView.swift`, `Views/AddTransactionView.swift`
  - `Views/BudgetSheet.swift`, `Views/CategoryLimitSheet.swift`, `Views/ImportView.swift`
  - `Views/Settings/HelpFeedbackSettingsView.swift`
  - `Views/Components/CardGradient.swift`, `Views/Components/RefreshNote.swift`
- Transitions: `Views/HomeView.swift`, `Views/CardDetailView.swift`, `Views/TransactionDetailView.swift`; `Views/ActivityView.swift` (day pages, flagged).

## Test plan

- `Feedback.delete.sensory == .impact(weight: .medium)`; `.undo` → light impact; `.fail` → `.error`; `.blocked` → `.warning`; `.save` → `.success`.
- Every `Feedback` case maps to a `SensoryFeedback` (exhaustive test).
- Grep check: no raw `.sensoryFeedback(` outside `Feedback.swift`.
- `MonthStep.direction(from: Aug, to: Sep) == .forward`; Sep → Aug `.back`; Dec 2025 → Jan 2026 `.forward`.
- Transition choice: `crossFade == true` → `.opacity`, whatever the direction.
- Day pager (flag on): day index from date, and back across a month edge.
- `ui-driver`:
  - zoom from Home Recent and from a card;
  - month change slides left or right;
  - Reduce Motion and Prefer Cross-Fade show fades only;
  - AX5 on the day pager.
- Device only: how each haptic feels. The simulator plays none.

## Gate

- Raj approves the table.
- The UI pass shows no Reduce Motion regressions.
- The day pager ships only after its own UI pass.

## Sources

- `docs/ux-research/02` and `03` (HIG haptics: consistent, sparing, paired with visuals).
- `docs/ux-research/07` (TeuxDeux).
- Apple's `SensoryFeedback` and HIG haptics pages did not render on 25 Sep 2026. Case names are taken from code that compiles in this repo. **`.warning` is not verified here.**

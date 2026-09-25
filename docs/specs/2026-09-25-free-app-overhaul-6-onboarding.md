# Overhaul 6: setup you can tap through, and the aha moment (25 Sep 2026)

Part of `2026-09-25-free-app-overhaul-overview.md`.

## Problem

Raj wants two things:
- "Allow the user to continually click Continue, set reasonable defaults."
- "Set an AHA activation moment."

Today's steps (`SetupFlow.Step`), read in code:

| Step | Shown when | Primary button today | Default if skipped |
|---|---|---|---|
| welcome | always | Get Started | — |
| goals | always | Continue | no goals |
| payment | always | "Skip This One"; a pick moves on by itself | none (Apple Pay step shown) |
| currency | always | Continue | phone's currency (`Money.detectedHome`); abroad: none |
| feeling | always | "Skip This One" | none |
| budget | goal "Spend less" | Continue | no limit |
| checkIn | always | **"Turn On Notifications" → system alert** | Sunday pre-picked, saved as "none" if not chosen |
| building | always | moves on after ~3.3 s, or tap | — |
| plan | always | "Add My First Card" (starts the chores) | — |
| cards | always | "Add Cards Later" | no cards |
| cardDetails | cards added | "Add Digits Later" | no digits |
| applePay | payment ≠ cash | "I'll Do This Later" | not set up |
| pro | always | deleted by sub-spec 1 | — |
| email | Gmail feature + wants Gmail (+ Pro today) | "I'll Do This Later" | not connected |

**No step disables Continue today.** I checked: there is no `.disabled` in `OnboardingView.swift`. The friction is elsewhere:
- about 12 screens to tap through;
- a system permission alert in the middle (checkIn);
- chores (cards, digits, Shortcut, Gmail) right after the plan.

## Options

| | A. Keep the steps, remove the stops (recommended) | B. Two screens ("about you", then the plan); chores move to Home | C. No setup; straight to Home with the checklist |
|---|---|---|---|
| Screens to tap through | ~9 | 3 | 1 |
| Personalisation | kept (research 02) | smaller | none |
| Work | 2 d | 4 d | 1 d |
| Risk | low | redesign; needs the flag | loses the "made for me" effect (Headspace data, research 02) |

## Recommendation

A, behind a DEBUG flag `SPEND_NEW_SETUP` until the UI pass.

**Setup changes:**
- On checkIn, the primary button says "Continue" and keeps Sunday. The notification alert moves to the aha moment (research 03 §9: "ask after the aha").
- On the plan, "Do this later" goes straight to Home. The chores live in the existing Finish Setup card (`FinishSetupCard.swift`).
- One plain, warm line per screen (heyclicky reference). The receipt-icon mascot waits for art from sub-spec 9.
- The welcome screen offers "Restore from iCloud" when sub-spec 3 finds a backup.

**Aha candidates:**
1. **First purchase that logs itself (recommended).** The aha is the first `Transaction` whose `seenIn` contains `.tap` or `.email`. It must not be sample data (`DemoData`) and must not be a Send a Test Tap purchase (`TapTestButton.testMerchant`). Home then shows:
   - one card: "Logged by itself. That's Sortd working.";
   - a success haptic and a tick. Celebrate the logging, never the spending (research 03 §11);
   - then the single notification ask: "Want a Sunday recap?".
2. **Setup proof.** The test tap succeeds, or the Shortcut reaches the app (`LogPurchaseIntent.shortcutHasReachedApp`). It comes sooner, in the same session, but proves only Sortd's half (`HANDOVER.md`). Record it as a milestone, not the aha.

**Measure** (sub-spec 2):
- the share of installs with `activation(source, hours_bucket)` within 24 h and within 7 d;
- `setup_finished(skipped)`;
- drop-off by `setup_step_viewed`.

Compare the old flow's baseline with the new flow.

Visual metaphor for the month (Focus Flight reference): not in this sub-spec. Home gets its own spec if Raj wants it.

## Files

- `Spend/Services/SetupFlow.swift`: pure; put the defaults here as `SetupFlow.defaults`.
- `Spend/Views/OnboardingView.swift`: checkIn button, plan exit, welcome restore.
- `Spend/Views/Onboarding/SetupPages.swift`: copy.
- `Spend/Services/SetupChecklist.swift`, `Spend/Views/Home/FinishSetupCard.swift`.
- New `Spend/Services/Activation.swift`: a pure detector plus a once-only UserDefaults flag.
- `Spend/Views/HomeView.swift`: aha card.
- `Spend/Services/Reminders.swift`: the permission ask moves here.

## Test plan

- Tapping only the primary button from welcome reaches `finish()` without asking for permission (a fake notification centre records 0 requests).
- Skipped defaults:
  - currency = detected home;
  - budget = 0;
  - check-in = Sunday, saved but not scheduled until permission;
  - goals = empty.
- `SetupFlow.path` for every combination of goals, payment and hasCards: never `.pro`, never more than 11 steps.
- `Activation.detect`:
  - `[manual]` → nil;
  - `[tap]` → `.tap`; `[email]` → `.email`;
  - a DemoData tap → nil;
  - a test-tap purchase (`testMerchant`) → nil;
  - a second call after success → nil (once only).
- Aha shown → the notification ask shows once. Declined → never again.
- Flag off → the old flow is unchanged (existing `SetupFlowTests` pass).
- `ui-driver`:
  - tap only Continue on SE and at AX5;
  - aha card with VoiceOver;
  - Reduce Motion.
- Device only: a real Apple Pay tap triggers the aha. A Gmail import triggers it.

## Gate

- Raj approves the aha definition and the move of the notification ask.
- UI pass on the flag.
- The flag is removed in a follow-up PR.

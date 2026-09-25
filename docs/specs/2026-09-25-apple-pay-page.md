# Apple Pay Logging page, redone (25 Sep 2026)

**Approved by Raj on 25 Sep 2026 with the defaults:** remove the test tap outright; Finish Setup ticks Apple Pay when the Shortcut first reaches the app; intro step 3 shows the tab bar then a swipe between days; existing installs see the intro once; keep five tips and drop the add tip.

## Problem

Raj on his iPhone 16 Pro Max: "Send a Test Tap… doesn't work. I can do it even without setting up the shortcut." He is right, and it is worse than a glitch:
- `TapTestButton.run()` calls `LogWalletTapIntent.handle` inside the app. Shortcuts is never involved, so it passes with no Shortcut installed.
- On the way it writes `LogPurchaseIntent.lastTapAtKey`. So a test tap alone flips the onboarding status to "Connected and running", ticks Apple Pay in the Finish Setup card and closes the Apple Pay tip. All three are false.
- The onboarding step (`OnboardingView.applePay`) and Settings (`SetupGuideView`) are two different screens, with three buttons each and different status wording.

## What Sortd can and cannot know

| Can know | Cannot know |
|---|---|
| The Shortcut ran and reached Sortd (`lastTapReceivedAt`) | Whether the Wallet automation exists, or which cards are ticked |
| A real tap was logged: date, shop, amount (`Transaction.seenIn` has `.tap`) | Whether Wallet will run the automation at a given till. Apple's trigger can time out waiting for the bank (FB14035016, FB16379100) |

## Options

| | A. Honest status, no test (recommended) | B. A + "Check the Shortcut" button | C. B, but it sends a test purchase |
|---|---|---|---|
| What | One status card, one main button, the picture guide. The test tap is removed. | Opens `shortcuts://x-callback-url/run-shortcut?name=Log%20Apple%20Pay%20in%20Sortd&x-success=sortd://…&x-error=sortd://…`, then shows the result | Same URL with `input=text&text=…`, so a made-up purchase goes through the real Shortcut |
| Proves | Only real events | The Shortcut is installed and reaches Sortd. That is the same as ▶ in Shortcuts. | The same, plus the text parser |
| False results | none | Says "not found" for anyone who built it by hand or renamed it. Says "works" with no automation. | Same as B, plus a purchase to delete |
| Work | 1–1.5 d | +1 d, plus a device spike | +1.5 d |
| Risk | low | URL flow on iOS 26/27 **not verified**: prompts, the return trip, and the empty `result` | same as B |

What I found for B: Apple documents `run-shortcut` with `name`, `input`, `text`, and x-callback `x-success` (adds `result`), `x-cancel` and `x-error` (adds `errorMessage`). The result reaches Sortd on its own: the intent runs Sortd's code and writes `lastTapReceivedAt`, so on return the page compares it with the time the check started. `result` is probably empty, because the intent returns only a dialog (**not verified**). It still cannot see the Wallet trigger.

## Recommendation

**A.** Every state on the page comes from a real event, so it cannot lie. B adds a second way to be wrong and still misses the part that fails, which is Wallet. First step: the pure `ApplePayStatus` and its tests.

**The shared panel** (`ApplePaySetupPanel`). The onboarding step and Settings › Apple Pay Logging both use it, and so do Help and the Finish Setup sheet, which already open `SetupGuideView`.
1. The status card. Only one of three states shows:
   - "Not connected yet" / "Get the Shortcut, then turn it on for your cards."
   - "Shortcut reached Sortd · Today 10:42" / "Now pay in a shop. The tap shows up here."
   - "Last tap logged · Today 12:05" / "A$4.50 at Seven Seeds". A VoiceOver label covers the amount.
2. The main button: **Get the Shortcut**. Below it, `WalletSetupGuide(route: .quick)` on iOS 27, or the numbered steps on iOS 26. Then "Open Shortcuts" as a secondary button.
3. One line: "Sortd sees when a tap arrives, not your automation." Then one line with a link: "Apple's trigger sometimes misses a tap, most often at vending machines, transport gates and parking. **Learn more**". The link goes to `sortd.page/support#apple-pay`.
4. "Rather do it by hand?" opens the by-hand guide.

Settings also keeps "Last Tap Received" (the raw text; support staff point people to it) and "Good to Know". It loses "Check It Works".

**One-time fix at launch** (`ApplePayStatus.settleTestTap()`): if the last raw tap text has merchant "Sortd Test" and there is no real tap, clear `lastTapReceivedAt`.

## Files

- New: `Spend/Services/ApplePayStatus.swift` (pure: `resolve(lastReachedAt:taps:now:)`, `settleTestTap`) and `Spend/Views/Components/ApplePaySetupPanel.swift`.
- `Spend/Views/OnboardingView.swift`. The Apple Pay step lives here (`applePay`, `tapStatus`, `firstTap`, `shortcutReached`, about lines 1043–1159), not in `SetupPages.swift`, which only holds `SetupCopy`.
- `Spend/Views/SetupGuideView.swift`, `Settings/PurchaseSourcesSettingsView.swift` (`lastTapText`), `Home/FinishSetupCard.swift` (`tapped:`), `App/SpendApp.swift` (settle call).
- Delete `Spend/Views/Components/TapTestButton.swift`. Move `testMerchant` to `LogPurchaseIntent.legacyTestMerchant`, so old test purchases stay excluded. It is used in `LogWalletTapIntent.swift:71`, `LogPurchaseIntent.swift:60`, `Services/Activation.swift:29`, `Services/Suggestions.swift:64`, and the tests `ActivationTests`, `SuggestionsTests` and `AnalyticsTests`.
- No SwiftData model change, so no migration and no `MigrationTests` change. No pbxproj edits.

## Risks

- **Less reassurance before the first purchase.** The page is honest: it waits for the first shop tap. The "reached" state covers the ▶ run. We would notice through the Analytics `setup_step_viewed` drop-off at the Apple Pay step, and `apple_pay_tap_logged` within 7 days.
- **The settle step wrongly clears a real "reached".** This only happens if the latest raw text was a test tap. The next ▶ or real tap sets it again. No data is lost.
- Old "Sortd Test" purchases stay in stores and stay excluded from activation and suggestions. They are not deleted.
- **Privacy label, App Review:** no change. Nothing new leaves the phone.
- The Learn more link lands on the general Apple Pay answer. A line about missed taps needs a site edit, which is not in this task.

## Test plan (Swift Testing)

- `resolve(nil, [], now)` → `.notConnected`.
- `resolve(10:42, [], now)` → `.shortcutReached(10:42)`.
- `resolve(10:42, [tap 12:05 "Seven Seeds" A$4.50])` → `.tapLogged(12:05, "Seven Seeds", 4.50, "AUD")`.
- `resolve(nil, [tap])` (restored backup) → `.tapLogged`.
- Only DemoData taps → `.notConnected`. Only `legacyTestMerchant` taps → `.notConnected`.
- Two taps → the later one. A tap merged with an email (`seenIn` has `.tap` and `.email`) → counts.
- `settleTestTap`:
  - raw text `merchant “Sortd Test”`, no real tap → `shortcutHasReachedApp == false`;
  - run twice → no change;
  - a real tap exists → kept.
- `LogWalletTapIntent.handle(nil)` (▶ run) → no `Transaction`, status `.shortcutReached`.
- Wallet text "Seven Seeds A$4.50 NAB Visa Debit" → `.tapLogged`.
- Each state's accessibility label has the shop and the formatted amount. The Learn more URL constant is `https://sortd.page/support#apple-pay`.
- Existing `ActivationTests`, `AnalyticsTests` and `SuggestionsTests` pass with the moved constant.

**ui-driver:**
- Onboarding step and Settings page in all three states (seed the defaults; `SPEND_REEL_TAP=2` for a tap).
- Sizes SE, Pro Max and AX5; dark mode.
- No "Send a Test Tap" anywhere.
- VoiceOver reads the status as one element.
- Learn more opens Safari.

**Device only (Raj):** Get the Shortcut → Replace → automation → a staffed till on Visa → the status reads "Last tap logged". This is also HANDOVER §4 item 8.

## Gate

Raj approves the three status lines, removing the test, and the one-line timeout note. Then a UI pass, the known-bug set unchanged, and one device tap.

## Open questions

1. Do we remove the test outright (A), or add B later as "Check the Shortcut is installed", after a device spike?
2. Should the Finish Setup row count as done on "reached" (as today) or only on the first real tap?

## Sources

- Apple, [Run a shortcut using a URL scheme](https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios) and [Use x-callback-url with Shortcuts](https://support.apple.com/guide/shortcuts/use-x-callback-url-apdcd7f20a6f/ios), read 25 Sep 2026. They list no iOS version and say nothing about what happens when a shortcut is not found.
- Apple Developer Forums, [Shortcuts Automation Trigger Transaction Timeouts](https://developer.apple.com/forums/thread/765516) (FB14035016, FB16379100), read 25 Sep 2026 through a search summary only.
- Worktree `/Users/kameshraj/Developer/Sortd/.claude/worktrees/idea-applepay-page`. I read: `CLAUDE.md`, `HANDOVER.md` (it has **no** Apple Pay section; the radars and shortcut notes came from `.claude/agents/support.md`, `.claude/agents/growth.md`, `scripts/build-apple-pay-shortcut.py` and `site/support.html`), `docs/AgentPipeline.md`, `docs/ux-research/02`, `docs/ux-research/07`, `docs/specs/…-6-onboarding.md` and `…-7-tips.md`, `Spend/Views/{OnboardingView,SetupGuideView,WalletSetupGuide}.swift`, `Views/Onboarding/SetupPages.swift`, `Views/Settings/PurchaseSourcesSettingsView.swift`, `Views/Components/{TapTestButton,Tips}.swift`, `Views/Home/{ActivationCard,FinishSetupCard}.swift`, `Intents/{LogWalletTapIntent,LogPurchaseIntent}.swift`, and a grep of `SpendTests/`.

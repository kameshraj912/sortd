# Spend — Raj's personal iOS spending tracker

Logs NAB (AUD) and StanChart SG (SGD) Apple Pay spending automatically and shows where the money goes. Personal use only, never on the App Store. Plan: `~/.claude/plans/can-you-make-me-tidy-dewdrop.md`.

## Build / test
- Open: `open Spend.xcodeproj` (Xcode 27, iOS 26+ target, SwiftUI + SwiftData + Swift Charts + App Intents).
- Build: `xcodebuild -project Spend.xcodeproj -scheme Spend -destination 'generic/platform=iOS Simulator' build`
- Test: `xcodebuild -project Spend.xcodeproj -scheme Spend -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test` (Swift Testing, in-memory store).
- Sample data in the simulator: launch with env `SPEND_DEMO=1` (DEBUG only), or tap "Explore with sample data" on the first screen.
- On the phone: Xcode → Signing & Capabilities → pick Raj's team. Free team = re-install every 7 days.

## Layout
- `Spend/App` — app entry, tabs, DEBUG sample data.
- `Spend/Models` — SwiftData models (`Transaction`, `MerchantRule`, `FXRate`) and enums (`Card`, `SpendCategory`, `TxnSource`).
- `Spend/Services` — parsing, categorising, de-duplication, logging, SGD→AUD rates.
- `Spend/Intents` — `LogPurchaseIntent`, called by the Shortcuts Wallet/Transaction automation.
- `Spend/Views` — SwiftUI screens; `Views/Components` holds shared rows and badges.
- `SpendTests` — unit tests for the pure logic.

## Rules for this codebase
- Every source goes through `TransactionLogger.log(_:in:)`. It categorises and de-duplicates. Never insert a `Transaction` directly (only `DemoData` does).
- Enums are stored as raw strings (`cardRaw`, `categoryRaw`, `sourceRaw`) so SwiftData predicates work.
- Totals use `audValue` (AUD). Keep the original amount and currency too.
- UI uses system components first (Apple HIG, Liquid Glass): SF Symbols, `.monospacedDigit()` on money, Dynamic Type, a VoiceOver label on every amount and chart.
- No bank passwords, no screen scraping. Secrets (the Google refresh token) go in the Keychain, never in git.
- The project uses folder-synced groups: new files under `Spend/` are picked up with no pbxproj edits.

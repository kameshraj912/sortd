# UI baseline — 2026-09-25

Pre-overhaul screenshots of `main`, taken per `docs/AgentPipeline.md` "Big changes and
overhauls" step 4, so later sub-spec UI passes have something to compare against.

- Commit: `c379a0e` (branch `baseline-ui`, off `main`)
- Device: iPhone 18 Pro, iOS 27.0, simulator `Sortd-baseline-ui`
- Data: `SPEND_DEMO=1` (the same data as "Explore with sample data")
- Modes: `default` = light, `large` text size. `dark` = dark appearance. `ax5` =
  Dynamic Type accessibility-extra-extra-extra-large (the largest step).

## Onboarding (every step, default only)

| File | Shows |
|---|---|
| `onboarding-0-welcome-default.png` | Welcome screen, "Get Started" / "Bring In Past Spending" / "Look around with sample data" |
| `onboarding-1-goals-default.png` | Goals question |
| `onboarding-2-payment-default.png` | Payment question |
| `onboarding-3-currency-default.png` | Currency question |
| `onboarding-4-feeling-default.png` | Feeling question |
| `onboarding-5-budget-default.png` | Budget question |
| `onboarding-6-checkIn-default.png` | Check-in question |
| `onboarding-7-building-default.png` | "Building" pause screen |
| `onboarding-8-plan-default.png` | "Here's your Sortd" plan summary and Finish Setup checklist |
| `onboarding-9-cards-default.png` | Add cards step |
| `onboarding-10-cardDetails-default.png` | Card details step |
| `onboarding-11-applePay-default.png` | Apple Pay shortcut step |
| `onboarding-12-pro-default.png` | Pro step at the end of setup |

## Home

- `home-default.png`, `home-dark.png`, `home-ax5.png` — Home tab: month total, budget line,
  sample-data banner, category bar, card carousel, "Where It Went" list.

## Activity

- `activity-default.png`, `activity-dark.png`, `activity-ax5.png` — Activity list grouped by
  day, with category filter chips.
- `activity-search-default.png` — Activity tab with the search field focused
  (`SPEND_SEARCH=1`).

## Purchase detail

- `detail-default.png`, `detail-dark.png`, `detail-ax5.png` — Uber Eats transaction detail
  sheet: amount, category, card, date, note.

## Add sheet

- `add-default.png`, `add-dark.png`, `add-ax5.png` — manual "Add Transaction" sheet.

## Insights

- `insights-default.png`, `insights-dark.png`, `insights-ax5.png` — Insights tab (Pro).

## Subscriptions and bills

- `subscriptions-default.png` — Recurring/subscriptions list (default only, per brief).

## Settings

- `settings-default.png`, `settings-dark.png`, `settings-ax5.png` — Settings root list
  (Sortd Pro row, Purchase Sources, Bills & Reminders, Cards & Appearance, Currency, Learned
  Categories, Privacy & Security, Backup & Data, Help & Feedback, About).

## Paywall

- `paywall-default.png`, `paywall-dark.png`, `paywall-ax5.png` — Sortd Pro paywall
  (`SPEND_PAYWALL_DEMO=1 SPEND_PRO=0`).

## Budget sheet

- `budget-default.png` — monthly budget editor sheet (default only, per brief).

## Not captured — no findings hunt, but recorded here for the record

The Settings sub-pages (Purchase Sources, Bills and Reminders, Currency, Privacy and
Security, Backup and Data, About) are each reached only by a `NavigationLink` tap from the
Settings list; the app has no `SPEND_SCREEN` case or `sortd://` URL route for them (only
`recurring` and `import` are wired to the router's deep link). This session's iOS Simulator
MCP control tool (`tap`/`screenshot`/`attach`) was not granted access to
`Sortd-baseline-ui` for the whole session (a prior request was declined or never
answered), and no windowed `Simulator.app` process existed for an AppleScript fallback, so
no tap-driven screen could be reached. `xcrun simctl openurl sortd://...` also fails: the
app registers no `CFBundleURLTypes`, so the scheme isn't routable from outside the app.
These six sub-pages are not in this baseline; whoever compares screens later should note
they're missing here, not that they're unchanged.

## Known-bug baseline

`scripts/test.sh --known-bugs` on the same commit: **21 known-bug tests fail** (all tagged; the CI suite is green). Names:

- aBackupWithTheSameIdTwiceMustNotAddItTwice
- aBackupWithTheSameIdTwiceMustNotAddItTwiceOnReplace
- aLowercaseHomeCurrencyStillCountsInTotals
- aMangledTapAmountIsNotStoredAsMoney
- aMinusAfterTheCurrencyIsStillARefund
- aNegativeAmountInABackupDoesNotSubtractFromTheMonth
- aPaddedCurrencyCodeStillCountsInTotals
- aReceiptThatMergesIntoAPendingDeleteIsLostForever
- aRechargeAfterARefundIsCountedAgain
- aRefundWithTheMinusAfterTheSymbolIsStillARefund
- aRowWithNoDateIsNotSilentlyDropped
- aTapWithNoAmountStillMergesWithItsReceipt
- aWrittenCurrencyTheAppSupportsIsKept
- absurdDatesAreNotImported
- anAbsurdlyLongNumberIsRefused
- anUnsupportedCurrencyIsNotLeftConvertingForEver
- currencySignsAreRead
- duplicateIdsSurviveASecondRestoreAndDoubleTheTotal
- extraDecimalsAreNotTurnedIntoThousands
- replaceRestoreMustNotKeepEmailIdsForPurchasesItDeleted
- theAmountBeatsAnyOtherNumberInTheText

## Added 26 Sep 2026 (bug hunt, docs/BugHunt-2026-09-26.md)
- aBankAlertWithNoGmailAuthenticationResultIsNotTrusted
- aBillInACurrencyWithNoRateIsNotShownAsZero
- aCRLFStatementKeepsEveryRow
- aCreditCardExportKeepsPurchasesAsSpending
- aFieldWithAWindowsLineBreakIsQuoted
- aForeignAmountInTheDescriptionIsNotThePurchase
- aRowWithNoSymbolTakesTheCardsCurrency
- aTapPostedAfterTheWeekendStillMerges
- aTextTapThatIsOnlyACardNameIsNotAPurchase
- aTransactionTypeColumnIsNotTheMerchant
- absurdYearsAreRejected
- justThisOneOnADeliveryOrderSurvivesALaunch
- justThisOneToOtherSurvivesALaunch
- mergeDoesNotReadASingaporeBudgetAsAustralianDollars
- narrowSpaceAndApostropheThousandsAreRead
- rupiahDotThousandsAreNotCents
- theFirstAmountInTheAlertIsThePurchase
- theWidgetReloadDateIsTheNextMidnightAcrossDaylightSaving
- zeroDecimalTotalsAreRead

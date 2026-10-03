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
- aRechargeAfterARefundIsCountedAgain
- aRefundWithTheMinusAfterTheSymbolIsStillARefund
- aRowWithNoDateIsNotSilentlyDropped
- aTapWithNoAmountStillMergesWithItsReceipt
- absurdDatesAreNotImported
- anAbsurdlyLongNumberIsRefused
- anUnsupportedCurrencyIsNotLeftConvertingForEver
- duplicateIdsSurviveASecondRestoreAndDoubleTheTotal
- extraDecimalsAreNotTurnedIntoThousands
- theAmountBeatsAnyOtherNumberInTheText

Removed 2 Oct 2026 with the Gmail feature (their tests only tested removed code):
aBankAlertWithNoGmailAuthenticationResultIsNotTrusted, aReceiptThatMergesIntoAPendingDeleteIsLostForever,
replaceRestoreMustNotKeepEmailIdsForPurchasesItDeleted, theFirstAmountInTheAlertIsThePurchase.

## Added 26 Sep 2026 (bug hunt, docs/BugHunt-2026-09-26.md)
- aBillInACurrencyWithNoRateIsNotShownAsZero
- aCRLFStatementKeepsEveryRow
- aCreditCardExportKeepsPurchasesAsSpending
- aFieldWithAWindowsLineBreakIsQuoted
- aForeignAmountInTheDescriptionIsNotThePurchase
- aRowWithNoSymbolTakesTheCardsCurrency
- aTapPostedAfterTheWeekendStillMerges
- aTransactionTypeColumnIsNotTheMerchant
- absurdYearsAreRejected
- justThisOneOnADeliveryOrderSurvivesALaunch
- justThisOneToOtherSurvivesALaunch
- mergeDoesNotReadASingaporeBudgetAsAustralianDollars
- narrowSpaceAndApostropheThousandsAreRead
- rupiahDotThousandsAreNotCents
- theWidgetReloadDateIsTheNextMidnightAcrossDaylightSaving
- zeroDecimalTotalsAreRead
- blankNotificationTriggerRealRunIsIndistinguishableFromAPreview (Apple Pay hunt 27 Sep: an all-blank iOS 27 Notification run looks like a ▶ test; needs a device spike, spec 2026-09-26 row 13)

## Added 2 Oct 2026 (budgets and bills hunt, FullBudget*Tests)
- aRaisedLimitCanAlertAgain (product decision: should raising a category limit re-arm its near/over alerts for the month?)

## Added 2 Oct 2026 (full-data backup hunt)
- aPurchaseTimeKeepsItsFractionOfASecond (backup dates are written with `.iso8601`, whole seconds only. Changing the date format risks older backups no longer reading, so it stays until Raj decides sub-second times matter)

## Added 2 Oct 2026 (safety-net polish)
- anUnconvertedForeignPurchaseIsNotMissingFromTheMonth (abuse-30: a foreign purchase with no exchange rate yet counts as zero in the widget's month total. Fails only on a machine with no cached rates, so it comes and goes between runs)

## Added 3 Oct 2026 (bug hunt, docs/BugHunt-2026-10-03.md)
Still failing on `fix-hunt-c`: these belong to the money, Apple Pay and statement findings that the other fix branches (`fix-hunt-a`, `fix-hunt-b`) own, plus the two rejected claims (S8, S9). Each fixer takes its names off this list when the fix lands.
- aForeignTapMergesWithItsStatementLine (S9, rejected: needs a design choice)
- reimportingAfterATapMergeDoesNotDouble (stmt-1)

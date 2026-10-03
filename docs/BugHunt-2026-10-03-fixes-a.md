# Bug hunt 3 Oct 2026: fixes, part A

Branch `fix-hunt-a` (from `hunt-20261003`). Findings from `docs/BugHunt-2026-10-03.md`:
money parsing, FX, quick entry, receipt camera totals, statement import, Deduper, export.
Every test below failed on the code before its fix (run and seen to fail), and passes after.
None is tagged `.knownBug`, so all run in CI.

| # | Result | Commit | Test |
|---|---|---|---|
| M1 | fixed | 5af3cab | `BugHuntFixesADatesTests.fxDayKeysAreGregorianOnAThaiOrJapanesePhone` |
| M2 | fixed | 3747229 | `BugHuntFixesAMoneyTests.everySupportedCurrencyIsReadBackAsThePhoneWritesIt` (every `Money.supported` code on en_AU, en_SG, en_US, en_GB), `dollarSignsWithACountryPrefixAreRead` |
| D1 | fixed | af77da1 | `BugHuntFixesADedupeTests.aTapTheNextDayDoesNotSwallowAHandTypedPurchase`, `aHandTypedPurchaseTheNextDayIsNotMergedIntoATap` |
| S1 | fixed | 5af3cab | `BugHuntFixesADatesTests.statementDatesAreGregorianOnAThaiOrJapanesePhone` |
| M3 | fixed | 321d4bb | `BugHuntFixesAQuickEntryTests.quickEntryReadsACodeBeforeTheNumberAndASignAfterIt` |
| M4 | fixed | 89e342f | `BugHuntFixesAReceiptTests.aTotalWithACodeAndASignIsRead` |
| M5 | fixed | 89e342f | `BugHuntFixesAReceiptTests.aTotalWithNoSignBeatsTheSubtotal` |
| M6 | fixed | 89e342f | `BugHuntFixesAReceiptTests.theCashHandedOverIsNotTheTotal` |
| M7 | fixed | 3747229 | `BugHuntFixesAMoneyTests.rsIsReadAsRupees` |
| M8 | fixed | 3747229 | `BugHuntFixesAMoneyTests.aWholeDollarAmountIsNotJoinedToTheNextNumber` |
| S2 | fixed | b64cc34 | `BugHuntStatement1003Tests.aZeroInTheUnusedColumnIsNotAPurchase` (reviewer's test, untagged) |
| S3 | fixed | b64cc34 | `BugHuntStatement1003Tests.aSemicolonCSVWithDecimalCommasIsRead` (reviewer's test, untagged) |
| S4 | fixed | 636a59d | `BugHuntStatement1003Tests.aWalletOrBankAppListIsRead` (reviewer's, untagged), `BugHuntFixesAImportTests.aWalletListTakesTheDayUnderEachPurchase`, `aBankAppListTakesTheDayAboveAndSkipsTheBalance` |
| S5 | fixed | 0267997 | `BugHuntFixesAImportTests.aStatementThatNamesNoCardIsNotFiledUnderTheFirstCard`, `aStatementRowWithNoCardMergesWithTheTapOnAnyCard` |
| S6 | fixed | 0279be1 | `BugHuntStatement1003Tests.aUTF16FileIsDecoded` (reviewer's test, untagged) |
| S7 | fixed | e2100c8 | `BugHuntStatement1003Tests.aHotelReceiptKeepsItsName` (reviewer's test, untagged) |
| D5 | fixed | 6930ec7 | `BugHuntFixesAExportTests.anExportIsNamedWithTheLocalDate` |
| D6 | fixed | 6930ec7 | `BugHuntFixesAExportTests.theCSVLeavesOutCheckRowsAndSamplePurchases` |

Also on the branch:
- 9266e1c: `BugHuntAccountTests.swift:114` did not compile (main-actor init in a default
  argument), so no test ran. Same one-line change as `fix-hunt-c`'s 5ef9955.
- 091c3f0: two actor warnings my changes added (`AmountParser` is now `nonisolated`).
- 5dc286d: abuse-12 `aWrittenCurrencyTheAppSupportsIsKept` and abuse-13
  `currencySignsAreRead` pass after M3, so they are untagged and off the baseline list.

## Decisions taken in the fixes

- **Calendar (M1, S1, D5).** New `DayKey`: Gregorian, in the phone's time zone.
  `FXService.dayString`, `StatementImport` and `Exports.dated` take a calendar with that as the
  default and use only its time zone, so a Buddhist or Japanese calendar passed in still gives
  2026. The other `Calendar.current` uses in `Spend/Services` were checked and left: month keys
  for budget alerts and the Pace nudge (`CategoryBudgets.monthKey`, `Pace.monthKey`) must match
  the months the screens total with the phone's calendar; `ApplePayStatus.when`, `Reminders`,
  `SortdVoice` and `DemoData` are display, scheduling or sample data, not keys or parsing.
- **NT$ (M2)** is read as TWD, which has no daily rate. That matches how "TWD 300" was
  already read, and is better than booking NT$300 as the local currency.
- **D1.** Between a hand-typed purchase and an Apple Pay tap, only the same calendar day
  merges. Statement rows keep the 2-day window. A typed 23:55 purchase and a 00:05 tap stay
  two rows (rare, and the user can delete one; a wrong merge loses a purchase).
- **S5.** The import starts on the card the statement's heading names (its digits or one
  card's bank words), else the only card, else "Card not known".
- **S4.** Only used when no line has a date and an amount together, so PDF statements read
  as before. Fixtures are synthetic OCR-style text; not checked against a real Wallet or bank
  screenshot.
- **M6.** "AMOUNT PAID" / "CASH" lines are skipped only when the receipt gives non-zero change.

## Seen while fixing, not fixed (not on this list)

- `BugHuntStatement1003Tests.aCSVWithAnAccountLineOnTopKeepsTheSalaryOut` (S8) and
  `aForeignTapMergesWithItsStatementLine` (S9) **fail** on this code, so both reproduce.
  The report lists them as rejected only because the verifier could not run tests. S9 needs a
  design choice (match on home value with an FX margin).
- `reimportingAfterATapMergeDoesNotDouble` (hunt-1003-stmt-1) fails and has no row in the report.
- A PDF line like "Statement period 1 Sep 2026 to 30 Sep 2026" is read as a purchase with
  the year 2026 as its amount (`parse(text:)` first pass, unchanged by these fixes).
- The 3 Oct reviewers' known-bug tests are not on the baseline list in
  `docs/ux-research/baseline-2026-09-25/README.md` (23 names, other areas and S8/S9/stmt-1).
  The list also still names `aTextTapThatIsOnlyACardNameIsNotAPurchase`, which no test has.

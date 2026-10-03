# Bug hunt 3 Oct 2026 — fixes, branch `fix-hunt-b`

Findings from `docs/BugHunt-2026-10-03.md`: Apple Pay tap and notification runs, Siri
questions, widgets, the Router. Every fix was proved first: its test failed on the hunt
code (`scripts/test.sh --known-bugs`, 3 Oct 2026), then passed after the fix. Each test now
runs in the plain suite, with no known-bug tag. None of these names was in
`docs/ux-research/baseline-2026-09-25/README.md`.

| # | Result | Commit | Test |
|---|---|---|---|
| P1 | fixed: the second trigger's report of one refund is noted, not applied again | a0c7375 | `BugHuntApplePayTests.aTillRefundAndItsNotificationTakeTheRefundOffOnce`, `twoRefundsFromOneTriggerBothCount`, `aWholeRefundAndItsNotificationRefundOnePurchase` |
| P2 | fixed: a tap joins a notification row only when the shops agree | 8173b49 | `BugHuntApplePayTests.anOnlinePaymentIsNotSwallowedByALaterTapAtAnotherShop`, `theSameShopSpelledTwoWaysStillPairs` |
| P3 | fixed: a notification joins a tap row only when the shops agree | 8173b49 | `BugHuntApplePayTests.aLaterOnlinePaymentIsNotFoldedIntoATapAtAnotherShop` |
| U1 | fixed: a code and a whole number ("TOP 10") is only a fallback amount; no code inside a word ("PANTRY 24") | a7db9ae | `BugHuntUITests.aShopNameThatStartsWithACurrencyCodeIsNotTheAmount`, `BugHuntApplePayTests.aCurrencyCodeInsideAShopWordIsNotTheAmount` |
| U2 | fixed: a time marks a date line only when no amount is on it | a7db9ae | `BugHuntUITests.aOneLineTapWithATimeIsStillLogged` |
| U3 | fixed: a health-check run never saves a card or posts a Logged notice | 2c49df2 | `BugHuntApplePayTests.theHealthCheckDoesNotSaveATestCard` |
| P4 | fixed: money received (received, sent you, deposited, credited) saves nothing; refunds still take the refund path | a7db9ae | `BugHuntApplePayTests.moneyReceivedIsNotLoggedAsSpending`, `aCreditedRefundIsStillARefund` |
| P5 | fixed: falls back to the Application Support queue file; "Saved for later" only after a real write, otherwise says it was not saved | b7e57f7 | `BugHuntApplePayTests.aTapThatCouldNotBeQueuedIsNotReportedAsSaved`, `aTapGoesToTheSecondQueueFileWhenTheFirstFails` |
| U4 | fixed: Siri questions use `Transaction.excludingLegacyTest`, like Home and Activity | 51cfce7 | `BugHuntUITests.siriLeavesOutTheHiddenCheckRows` |
| U5 | fixed: Recent and Today widgets drop `Transaction.lacksShop` rows ("Unknown merchant") | 9393b50 | `BugHuntUITests.aTapWithNoShopIsLeftOutOfTheRecentWidget` |
| U6 | fixed: `sortd://scan` opens Add straight into the receipt scanner (the + menu's Scan too) | b33426c | `BugHuntUITests.theScanLinkOpensTheReceiptScanner` (router only; the screen was not checked by hand) |
| U7 | fixed: the needs-a-check notice opens `sortd://purchase/<id>` | 3423b1c | `BugHuntUITests.aNeedsACheckNoticeOpensThatPurchase` |
| P6 | fixed: a notification line with no amount is kept whole ("Cafe on Collins") unless a card is joined on | a7db9ae | `BugHuntApplePayTests.aShopNameWithAJoiningWordIsKeptWhole` |

Also: dcba6d0 adds `nonisolated init()` to `HuntAttester` in `BugHuntAccountTests.swift`,
so the test target compiles (the hunt commit noted the account fixer would do this too).

Runs on 3423b1c (iPhone simulator `Sortd-fix-hunt-b`, iOS 27): `scripts/test.sh`
1202 tests passed. `scripts/test.sh --known-bugs`: 59 known-bug tests fail. Before these
fixes it was 73 (59 + the 14 fixed here), so nothing new. 39 of the 59 are on the baseline
README list. The other 20 are other areas' 3 Oct hunt tests (BugHuntAccountTests,
BugHuntStatementTests, BugHuntSecurityTests), which are not on the README yet.

Not done here:
- Cards already named "Test Card" from earlier health checks are not removed.
- P1's refund reports sit in the app's reach defaults (row id, amount, currency, time,
  trigger; no shop or card), at most 50.

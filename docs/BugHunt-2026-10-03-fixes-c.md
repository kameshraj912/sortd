# Bug hunt 3 Oct 2026: fixes, branch `fix-hunt-c`

Findings X1, D2, D3, D4, A1, A2, A3, A4, X2, D7, A5, A6, X3, X4, X5 from `docs/BugHunt-2026-10-03.md`.
Every test below failed on the code of that day (the 12 hunt tests were run with `--known-bugs` first; D2's was run once with the fix line removed) and passes now in the normal suite.

| # | Result | Commit | Test |
|---|---|---|---|
| X1 | fixed: a cancel on Apple's confirm sheet returns at once (nothing deleted, nothing queued, analytics id put back); the view no longer wipes data | 26c500b | `cancellingApplesConfirmSheetCancelsTheDelete`, `aCancelledConfirmationStopsTheDelete` |
| A1 | fixed: `DCError.serverUnavailable` is offline, so the PostHog delete is queued; other App Attest errors are one plain sentence | c724126 | `anAppAttestServerOutageQueuesThePersonDelete`, `anAppAttestRefusalIsShownInPlainWords` |
| A2 | fixed: the Worker's code goes to the log; the alert says the usage record was not deleted and gives support@sortd.page | c724126 | `aWorkerRefusalIsShownInPlainWordsNotAsACode`, `a502IsRejectedForGoodNotRetried` |
| A3 | fixed: a failed Apple sheet (not a cancel) gives Apple's manual steps | c724126 | `aFailedAppleConfirmSheetGivesTheManualSteps` |
| A5 | fixed: Sign Out and a new Google sign-in move the old token to the revoke list | 79e6742 | `signOutFromGoogleForgetsTheGoogleToken` |
| X3 | fixed: a token stays on the pending list until Google answers 200/400; 20 s timeout | None | `gmailCleanupKeepsTheTokenUntilGoogleConfirms` |
| X4 | fixed: example file value is empty; the app treats an example host or `replace_me` as no Worker | e98839d | `exampleWorkerURLIsNeverUsedAsARealWorker`, `aPlaceholderWorkerURLCountsAsNoWorker` |
| D2 | fixed: a failed save deletes its pending row | d1d36b5 | `aFailedSaveLeavesNoRowSoARetryDoesNotSaveTwice` |
| D3 | fixed: a backup stops with `newerInCloud` when iCloud's copy is newer than this phone's last backup; restore (Add What's Missing) clears it. Also the reviewer's `deleteAllOnARestoredPhone...` test: Delete All's wiped last-backup date now counts | 4a2ce86 | `anOlderPhoneDoesNotWriteOverANewerICloudCopy`, `deleteAllOnARestoredPhoneStillRefusesToOverwriteTheOtherPhonesBackup` |
| A4 | fixed: Delete iCloud Copy counts as a reset, so a running upload removes its copy when it lands | None | `deleteICloudCopyDuringAnUploadLeavesNoCopy` |
| D7 | fixed: switching off cancels the waiting retry/catch-up/debounce | None | `aRateLimitRetryDoesNotUploadOnceBackupIsSwitchedOff` |
| A6 | fixed: same fix and test as D7 (same cause) | None | same |
| D4 | fixed: recovery screen, no `fatalError`; report via `ErrorLog`; old store moved aside, not deleted; screenshot `.build/store-recovery.png` (not committed) | b3daa30 | `theRestoredMessageCountsPurchasesInPlainWords` (the screen itself was checked by screenshot with `SPEND_STORE_FAIL=1`) |
| X2 | fixed: bill names use `ShopName` (always private); VoiceOver says "A bill" while locked | b1c3d29 | `billsWidgetKeepsShopNamesPrivateWhileLocked` |
| X5 | fixed: the run log keeps only empty / placeholder / length per field, in every build; old lines cleared once | 8cf6cad | `aDeletedTapLeavesNoShopOrAmountInDefaults`, `aRunLineSaysHowFieldsArrivedNotWhatTheySaid`, `runLinesFromOlderBuildsAreClearedOnce` |

## Notes

- Test Keychain: the unsigned test host cannot write the real Keychain (every write failed), so under XCTest `Keychain` keeps items in memory. Without this the A5 and X3 tests could never pass.
- D4 limits: after any recovery the app asks the person to close and reopen it (the rest of launch only runs on a store that opened). Siri question intents still read the empty in-memory store while the recovery screen is up. Not run on a device; the Restore buttons were not tapped in the simulator.
- X5 limits: the "Last Tap Received" alert and Developer menu now show field shapes, not words, so a phone check can no longer read the raw Shortcut text. Raj's call if that diagnostic matters more than the privacy gain.
- D3 limits: each automatic backup now also fetches the iCloud record to read its date (one extra download per backup, at most every 10 minutes).

# TestFlight hand-off — 4 Oct 2026

Start the TestFlight chat from this file. It says what is ready, what was checked, and the
steps left. Version **1.0**, build **1** (never uploaded). Archive from `main` at the commit
that merges `fix-phone-run`.

## Ready

- All bug-hunt fixes merged: A, B, C, D (#115, #116, #120, #121), the UI pass (#118), the
  shortcut link and privacy pages (#119), and the phone-run fixes (`fix-phone-run`).
- Release build settings: `SORTD_SIGNIN SORTD_ICLOUD`, no `SORTD_REPLAY` (#114).
- **CloudKit `Backup` record type deployed to Production** (4 Oct; fields `blob` asset and
  `modified` date; checked in the Production schema afterwards).
- Website live: free only, no screen recording, support page links our own shortcut file.
- Shortcut: `sortd.page/apple-pay.shortcut`, built by `scripts/build-apple-pay-shortcut.py`,
  signed (Apple cert, no personal name), valid to **26 Oct 2027**. Re-sign before then.
  An iCloud share link was made from Raj's phone on 4 Oct and is no longer used anywhere.
- Text to paste: `docs/TestFlightWhatToTest.md` (beta description + What to Test),
  `docs/AppReviewNotes.md` (review notes), `docs/ReleaseNotes-1.0-1.md`.
- Requirements research: `docs/research/2026-10-03-testflight-requirements.md` on branch
  `applepay-bank` (pushed).

## Checked

- Tests: full suite passes on the final branch; known-bug failures all on the baseline list.
- Simulator (`docs/testing/ui-pass-2026-10-04.md`): iOS 26 Apple Pay page, search open/close,
  App Lock (match, no match, retry), 300-action monkey test. No crash.
- Raj's iPhone 17 Pro, iOS 27, Release build (`docs/testing/phone-run-2026-10-04.md`):
  shortcut import with both triggers, a real tap logged, Check the Shortcut, iCloud backup,
  Save a Backup, Delete All Data, uninstall, reinstall, restore from file, onboarding, add /
  delete / undo, search, Insights, widget, App Lock unlock through Mirroring (Mac Touch ID).

## Not verified

- VoiceOver: code scan only, nobody listened to it on screen.
- Face ID on the phone itself, a real shop tap on the final build, an online Apple Pay
  payment through Wallet's notification, the feel check: Raj, in person.
- Restore from iCloud on a signed build with a real backup (only "no backup" was seen).
- Simulator-only: tapping Restore from iCloud in a script build aborts (unsigned, no iCloud
  entitlement). Signed builds are fine.

## Steps left (in order)

1. **Raj:** App Store Connect → accept the Terms of Service ("Agree"). It was waiting on
   4 Oct. Check Business › Agreements is clear.
2. Create the app record: iOS, name **Sortd** (if taken, Raj picks), primary language
   English (Australia), bundle ID `com.kameshraj.sortd`, SKU `sortd-ios`. Bundle ID and SKU
   can't change later. Needs Raj's OK.
3. Archive Release 1.0 (1) from a clean worktree at `main`, Validate, then upload. Do not tick
   "TestFlight Internal Testing Only".
4. TestFlight › Test Information: beta description, feedback email `support@sortd.page`,
   marketing URL `https://sortd.page`, privacy URL `https://sortd.page/privacy`,
   Beta App Review contact (Raj's phone in +61 format — only Raj can give it), sign-in not
   required, review notes from `docs/AppReviewNotes.md`.
5. Internal group with Raj first. Install from TestFlight and repeat the in-person checks.
6. External group → submit for Beta App Review (first build: plan for 1–6 days).
7. After upload: bump `CURRENT_PROJECT_VERSION` before any next upload.

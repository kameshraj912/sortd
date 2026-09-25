# Overhaul 3: automatic iCloud backup (25 Sep 2026)

Part of `2026-09-25-free-app-overhaul-overview.md`.

## Problem

Raj wants a "backed-up account": purchases that survive losing the phone. Today there is no automatic backup, so losing the phone loses everything (`CLAUDE.md` known gaps; `HANDOVER.md` still-to-do 3). The only protection is a manual file, `Backup.Snapshot` (`Spend/Services/Backup.swift`), and people forget to make it.

## Options

| | A. Snapshot to CloudKit private DB (recommended) | B. SwiftData CloudKit sync | C. Encrypted blob to Google Drive `appDataFolder` | D. Backend (Firebase or Supabase) |
|---|---|---|---|---|
| What | Encrypt the existing `Backup.Snapshot`, save it as one `CKAsset` record, daily and after big imports | `ModelConfiguration` with CloudKit; live sync across devices | Same blob, in Drive's hidden app folder (`drive.appdata`, a non-sensitive scope) | Real accounts and a cloud database |
| No server of ours | yes | yes | yes | **no** |
| Sign-in needed | no (uses the phone's iCloud account) | no | Google sign-in | yes |
| Migration | none | **yes**: `SchemaV2` drops `.unique` on 3 models | none | n/a |
| Cost to us | none (user's quota; forum sources) | none | none | per user, plus a security surface |
| Syncs a second device | no (restore only) | yes | no | yes |
| Gmail / CASA | Gmail data on Apple's servers, not ours (not checked with Google) | same | on Google's servers | **CASA certain**: Gmail data on our server |

Sign in with Apple adds nothing to A or B. CloudKit uses the phone's iCloud account.

## Recommendation

A. It reuses a tested format and restore path (`BackupTests`), needs no model change, and keeps "no server of ours" true. B can come later as its own migration-first sub-spec, if Raj wants live sync across devices. C only for people without iCloud, after sign-in (4). Not D.

First step: `CloudBackup.save(_:)` and `CloudBackup.fetch()` behind a protocol, tested with a fake store.

## Protection

- **Encryption.** Encrypt on device with CryptoKit AES-GCM. The key goes in a synchronizable Keychain item (iCloud Keychain, which Apple end-to-end encrypts). The key never goes in the CloudKit record. If the key is lost, the backup cannot be read. Offer an optional recovery key in Settings that the user can save. **Not verified:** what happens to the key when the user resets end-to-end data during iCloud recovery.
- **Quotas.** iCloud private DB storage is billed to the user's iCloud quota, not to us (forum sources, not Apple docs).
  - `quotaExceeded` → "iCloud is full; backup paused".
  - `requestRateLimited` → retry after `retryAfterSeconds`.
- **No abuse surface.** We run no endpoint.
- **Label.** Apple: "collect" means data leaves the device in a way we or partners can read. We cannot read a user's private DB, so it should stay "not collected". That is my reading of the definition. **Not verified.**
- **Lifecycle.**
  - Delete All Data also deletes the CloudKit record.
  - Settings: "Back up to iCloud" switch, last backup time, Back Up Now, Restore.
  - Turning the switch off offers to delete the iCloud copy.

## Files

- `Spend/Services/Backup.swift`: reuse `Snapshot`, `encode`, and `restore(_:mode:into:)`.
- New `Spend/Services/CloudBackup.swift`.
- `Spend.entitlements`: iCloud and CloudKit container. **Needs the paid developer account**, which is still pending.
- `Spend/App/SpendApp.swift`: schedule the backup after the active-phase tasks.
- `Spend/Views/Settings/BackupDataSettingsView.swift`, `Spend/Views/DataControlsView.swift`.
- `Spend/Views/OnboardingView.swift`: welcome shows "Restore from iCloud" only when a backup exists. Built in sub-spec 6.

Note for `code-reviewer`: `Backup.restore` inserts `Transaction` rows directly, matched by id (`Backup.swift:379`). That exception already exists, but `CLAUDE.md`'s rule names only `DemoData`. Restore must reuse that path. It must not add a new insert path, and must not route restored rows through `TransactionLogger` (that would re-merge them). Router: add the exception to `CLAUDE.md`.

## Test plan

- Snapshot → encrypt → decrypt: equal to the input, every field included (`imported` too).
- Wrong key: decrypt throws. The store is unchanged.
- Cloud restore calls `Backup.restore` with the decrypted data. Restoring the same backup twice adds nothing the second time.
- Restore when purchases exist: the user picks Replace or Merge. Replace shows `Backup.replaceWarning`.
- Fake store returns `quotaExceeded`: status "iCloud is full". Local data untouched.
- Fake store returns `requestRateLimited(30 s)`: next try is scheduled 30 s or later.
- Delete All Data: the fake store's record is deleted.
- Switch off: no save calls.
- `ui-driver`: Backup page in every state (never, just now, failed, iCloud off), at AX5; VoiceOver reads the last-backup time.
- Device only:
  - save, then restore on a second device or after an erase;
  - signed out of iCloud gives a clear message;
  - the Keychain key arrives on the second device.

## Gate

- Raj approves.
- Paid enrolment is active.
- A restore round-trip passes on a real device.

## Sources (read 25 Sep 2026)

- [CKError requestRateLimited](https://developer.apple.com/documentation/cloudkit/ckerror/code/requestratelimited), [quotaExceeded](https://developer.apple.com/documentation/cloudkit/ckerror/code/quotaexceeded)
- Billing and quota: [forum 665612](https://developer.apple.com/forums/thread/665612), [forum 35633](https://developer.apple.com/forums/thread/35633)
- No `.unique` with CloudKit: [fatbobman](https://fatbobman.com/en/snippet/rules-for-adapting-data-models-to-cloudkit/), [Hacking with Swift](https://www.hackingwithswift.com/quick-start/swiftdata/how-to-sync-swiftdata-with-icloud). Apple's page did not render; `Backup.swift:6-10` says the same.
- [Drive appDataFolder](https://developers.google.com/workspace/drive/api/guides/appdata)
- [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)

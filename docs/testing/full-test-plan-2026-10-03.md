# Sortd full test plan (bug hunt, crash hunt, abuse test, security check)

Written 3 Oct 2026 for the first TestFlight build. Plain words on purpose.
Read-only research: web, the repo at `/Users/kameshraj/Developer/Sortd`, and local `xcodebuild`, `xcrun xctrace`, `xcrun simctl` help pages (Xcode 27.0, macOS 27.0). Nothing in the repo was changed.

How to read the tags:
- `[S]` = spotted while reading code, NOT verified. Treat as a lead. Prove it with a run before calling it a bug.
- `[R]` = recently changed code (last 7 days). Test these first.
- `[M:STORAGE-1]` etc. = the MASVS control the line serves.
- `[B]` / `[H]` = from the 22 and 26 Sep hunts (check they have not come back). No tag = new idea.
- "not verified" = I could not confirm it from a page or a run.

---

## Bottom line

Most of Sortd's risk is not network security. It has no backend that holds money or purchases. The real risks are (1) **data loss and wrong money** (SwiftData store, CloudKit backup and restore, parsers, FX, dates and locales), (2) **privacy leaks** (widgets, notifications, app-switcher snapshot, logs, analytics under the consent switch), and (3) **the first-run path** (onboarding, Shortcuts automation, Apple Pay logging, App Attest on the real TestFlight build). The plan below turns the generic guides into 8 attack-list sections, 3 test runs (simulator tools, phone run, TestFlight checks) and one sign-off list. Four leads from reading the code deserve a run first: (a) `FXService.dayString` uses `Calendar.current`, which would give year 2569 on a Thai phone [S]; (b) `SpendStore.swift:52` ends the app with `fatalError` if the store cannot open [S]; (c) the widget summary file in the app group is plain JSON with shop names and amounts [S]; (d) `scripts/device.sh` builds Debug, so Sentry, iCloud and App Attest cannot be tested on the phone from that script; only a Release or TestFlight build can [S]. Also: only the iOS 27.0 simulator runtime exists on this Mac, while the app targets iOS 26.0, so the whole compatibility stage needs an iOS 26 runtime download first.

---

## Stage table (the plan in one table)

| # | Stage | What | Owner | Status | Time |
|---|---|---|---|---|---|
| 1 | Plan | This file. Raj approves the order. | Coordinator + Raj | draft | 15 min |
| 2 | Unit | `scripts/test.sh`, then `--known-bugs`. Read every failure. | Simulator agent | not started | 20 min |
| 3 | Tool runs | ASan, TSan, UBSan, strict concurrency, MallocScribble, Instruments (section B) | Simulator agent | not started | 2 to 3 h |
| 4 | Functional | Attack lists A1 to A6 (inputs, links, sign-in, backup, onboarding) | Simulator agent (abuse-tester, ui-driver) | not started | 1 day |
| 5 | UI | SE, Pro, Pro Max, AX5, dark, Reduce Motion, VoiceOver, Increase Contrast | Simulator agent (ui-driver) | not started | 3 h |
| 6 | Compatibility | iOS 26.x simulator smoke test, iPad check, 26 vs 27 feature hiding (A7) | Simulator agent | blocked: needs iOS 26 runtime | 2 h + download |
| 7 | Performance | Numbers in A8 and B | Simulator agent, then phone | not started | 3 h |
| 8 | Security | MASVS lines (A1), proxy capture, Worker curl tests | Simulator agent | not started | 4 h |
| 9 | Monkey | Random taps and text, 300 actions, ASan on (A6) | Simulator agent | not started | 2 h |
| 10 | Phone run | Section C, steps 1 to 70, via iPhone Mirroring | Phone via mirroring, Raj for Face ID, camera, Apple Pay | not started | 3 h + 45 min Raj |
| 11 | Usability | First-time-user timed pass, no sample data (C2) | Raj (or a friend who has never seen the app) | not started | 30 min |
| 12 | TestFlight checks | Section A9: clean device, upgrade, expiry, feedback, prod App Attest | Raj | not started | 1 h |
| 13 | Acceptance | Feel check and sign-off list (C3) | Raj in person | not started | 20 min |
| 14 | Report | One findings table (section D), verified by `finding-verifier` | Coordinator | not started | 1 h |

---

## Priority order: recently changed code first

From `git log --since='7 days ago'` (50 commits read) and the docs:

1. **Apple Pay online and the iOS 27 Notification trigger** `[R]`: PR #105 `applepay-online`, commits 1624503, 627488c, 44cab56, 4f32cba ("Logged" notification), d781dca. Spec `docs/specs/2026-09-26-apple-pay-failsafes.md` (edited 3 Oct). Sections: A5.
2. **ErrorLog, saveReporting, Connectivity catch-up, offline Delete Account** `[R]`: d1105d0, 692af67, 50a33c2, 3f850cd (PR #104 `polish-safety`). Sections: A4, A2.
3. **Polish slices** `[R]`: PR #107 `polish-feel`: press states and haptics (d0e78c6), 44 pt targets (ce8323e), buttons lock while work runs (905ead8), half-typed purchase kept for a day (3cd4398), empty states (95797d4), Budget Pace Alert off when iOS blocks notifications (93aa2c0), month tip (729ffc6), setup cards step (b408e7e). Sections: A6, A8 (spam-click), A5.
4. **Money and backup fixes** `[R]`: PR #103 `fix-money-hunt`, PR #102 `fix-backup-hunt`. Do "minesweeper" around each (A6).
5. **Widgets** `[R]`: PR #99 `widgets-four`. Sections: A1 (storage), A3.
6. **Gmail removal (2 Oct)** `[R]`: `Spend/Services/GmailCleanup.swift` and `GoogleAuth.swift` stay. Check no Gmail words, scopes or Keychain items are left, and that "Continue with Google" only asks for identity. Section A4.
7. **Activity rebuild** `[R]`: named by the coordinator; I did not see its commit among the 50 titles I read. Run `git log --oneline -- Spend/Views/ActivityView.swift` to find it. Check: day pager, search, `sortd://purchase/<id>` open, scroll with 10,000 rows.

---

## Spotted while reading (all "spotted, not verified")

| ID | Where | What I saw | How to prove it |
|---|---|---|---|
| S-01 | `Spend/Services/FXService.swift:12-14` (`dayString`) and `:256` | Uses `Calendar.current`. On a Buddhist-calendar phone (Thailand) the year would be 2569, on a Japanese calendar the era year. That string goes into the Frankfurter URL and into FX rate keys. Other places use `en_US_POSIX` or `Calendar(identifier: .gregorian)` (`ReceiptScanner.swift:179`), so this one looks missed. | Launch with `-AppleLocale th_TH@calendar=buddhist` (A2). Log a USD purchase; read the request URL and the `FXRate` key. Pass: 2026. |
| S-02 | `Spend/Services/SpendStore.swift:50-52` | `fatalError` when the store cannot open. The intent path is safe (`containerForIntent`, `TapQueue`), the app launch path is not. Disk full, corrupt file, failed migration all lead to a crash loop on every launch. `SpendMigrationPlan.stages` is empty (line 21). | A2: fill the disk, corrupt the store file, launch. Decide if "crash loudly" is acceptable or needs a recovery screen. |
| S-03 | `Spend/Services/WidgetSummary.swift:141-144` | Widget summary JSON is written with `.atomic` only, to the app group container. No explicit file protection class. It holds shop names and amounts (see `WidgetBridge.swift:145`). `Exports.swift:19-22` does use `.completeFileProtection`, so the team knows the option. | Open the file with `simctl get_app_container <udid> com.kameshraj.spend groups`. Read it. On the phone, check the Lock Screen widget while locked. |
| S-04 | `Spend-Info.plist`, `Spend.entitlements:10` | No `NSAppTransportSecurity` key (good: ATS defaults on). App Attest entitlement is `development`. Apple says apps always run in production after TestFlight or App Store distribution, so this is likely fine. [6] | A9: one real Delete Account from a TestFlight build must reach the prod Worker with a production attestation. |
| S-05 | `scripts/device.sh:9-24` vs `CLAUDE.md` | Script builds Debug and says Debug uses `Spend-Development.entitlements` (app groups only). `CLAUDE.md` says both configs sign with `Spend.entitlements`. Debug also turns Sentry off (`CrashReporting.swift:28-39`). | Check the signed entitlements: `codesign -d --entitlements :- <app>`. For iCloud, sign-in, Sentry, App Attest use a Release or TestFlight build. |
| S-06 | `Spend/Services/ErrorLog.swift:46-47` | Stores `error.localizedDescription` (cut to 120 chars) in UserDefaults. The comment says no merchant or amount, but a system error text may contain one. It only stays on the phone (shown in Developer menu). | Make a CSV import fail on a row with a distinctive merchant. Read `errorLog.recent` in the container plist. |
| S-07 | `Spend/Services/Router.swift:61,84-89` and `SpendApp.swift:376-379` | `.onOpenURL` runs for any app or website that opens `sortd://`. There is no source check (MASTG-TEST-0371 [3]). The router only navigates, so impact looks low. Unknown name goes to Home; bad purchase id goes to Activity silently (`:98-99`). While locked, the link still sets the tab behind the lock cover. | A3. Pass: a link never writes or deletes anything, and shows nothing while locked. |
| S-08 | `Spend/Services/FXService.swift:256,277-278` | `URL(string: ".../\(currency)...")!` force unwrap with text from data. `latestRate` does not check the HTTP status. Probably a closed list of currency codes. | Fuzz the currency code (A1, A6). Pass: no crash on any card or backup currency string. |
| S-09 | `Spend/Services/Analytics.swift:123` | Salt for the analytics id is fixed in the app (comment says on purpose). Anyone with the app can read it. The hash is only private as long as the Apple or Google subject id is unknown. Low. | Note in report. No run needed. |
| S-10 | `docs/TestFlightWhatToTest.md` | Says "There is no Sortd server". There is the account Worker, PostHog and Sentry. Also says sessions are recorded in the beta (the Release config has `SORTD_REPLAY`, `project.pbxproj:430`; `docs/AppStoreChecklist.md` says remove it for the App Store). Wording could mislead testers. | Fix the words; test that replay stops when consent is off (A1). |
| S-11 | `Spend/Services/Keychain.swift:25`, `KeychainBackupKeyStore.swift:59` | Classes look right: this-device-only for the Google token, synchronizable `AfterFirstUnlock` for the backup key. `Keychain.deleteAll` runs on Delete All Data only, and iOS Keychain items usually survive an app delete (not verified here). | A4: delete the app, reinstall, check what the Keychain still holds. |

---

# Section A. New attack-list sections

Same style as `docs/testing/attacks.md`: input → what should happen. Each line a reviewer can try. Obsolete: the `gmail-security` section of `attacks.md` (Gmail left on 2 Oct). Do not run it. Replace with A4.

Setup used in many lines: simulator `U=$(scripts/sim.sh boot)`; app bundle id `com.kameshraj.spend` (from `project.pbxproj:388`); launch with env via `SIMCTL_CHILD_<NAME>=1 xcrun simctl launch $U com.kameshraj.spend` (simctl help says the `SIMCTL_CHILD_` prefix passes env to the app).

## A1. security-masvs

MASVS v2 has 8 groups (STORAGE, CRYPTO, AUTH, NETWORK, PLATFORM, CODE, RESILIENCE, PRIVACY) [1]. MASTG test IDs below are from the MASTG test index [2]. The one-line control meanings are my paraphrase of MASVS v2 from memory; the page I fetched showed IDs only (not verified word for word).

### A1.1 Control map for Sortd

| MASVS control | Applies? | Sortd check (short) |
|---|---|---|
| STORAGE-1 (store sensitive data safely) | Yes | SwiftData store, UserDefaults, Keychain, app group JSON, CSV export, CloudKit blob. MASTG 0052, 0299, 0302, 0388. |
| STORAGE-2 (no leaks) | Yes | Unified log, snapshot, pasteboard, keyboard cache, notifications, third parties. MASTG 0053, 0054, 0055, 0058. |
| CRYPTO-1 (strong primitives) | Yes | Backup is AES-GCM (CryptoKit) with a 256-bit key (`KeychainBackupKeyStore.swift:44`). Two backups of same data differ; one flipped byte fails cleanly. MASTG 0061, 0063. |
| CRYPTO-2 (key management) | Yes | Key in synchronizable Keychain item, never in the record. Hardcoded keys (MASTG 0213): only the analytics salt `[S-09]`, not a crypto key. |
| AUTH-1 (remote auth) | Yes | Worker: App Attest per call. Sign in with Apple / Google PKCE. Test with curl (section B). |
| AUTH-2 (local auth) | Yes | App Lock with `LAContext` `.deviceOwnerAuthentication` (`AppLock.swift:209-224`). Event-bound, no Keychain binding, no enrolment-change check (MASTG 0266 to 0271). Accepted risk for a UI lock; write it down. |
| AUTH-3 (extra auth for sensitive actions) | Yes | Delete All Data and Delete Account: confirmation steps, fresh Apple code (README says codes last 5 minutes). |
| NETWORK-1 (secure TLS) | Yes | No ATS exceptions in `Spend-Info.plist`. Capture all traffic: only HTTPS, only known hosts. MASTG 0322, 0342, 0348. |
| NETWORK-2 (identity verification, pinning) | Partly | No pinning. Skip pinning tests (0068, 0385): free public APIs, no secrets in transit. Do check the app refuses a proxy cert that is not trusted. |
| PLATFORM-1 (IPC) | Yes | `sortd://`, App Intents, app group, widgets, notification actions. MASTG 0075, 0370, 0371, 0072. |
| PLATFORM-2 (WebViews) | Skip | No `WKWebView` or `SFSafariViewController` found in `Spend/` (only `GoogleAuth.swift` matched my grep for web-auth APIs). Re-run the grep before release. |
| PLATFORM-3 (UI) | Yes | App-switcher snapshot cover (`SpendApp.swift:284-290`), widget `privacySensitive`, screenshots, keyboard cache on merchant and note fields. MASTG 0059, 0290, 0055, 0313. |
| CODE-1 (current OS) | Yes | Target is iOS 26.0. Test on 26 (A7). |
| CODE-2 (forced updates) | Skip | TestFlight builds expire in 90 days [7]. No server to force updates. |
| CODE-3 (known-bad dependencies) | Yes | `posthog-ios`, `sentry-cocoa`: list versions from `Package.resolved`, check their advisories. MASTG 0273, 0275. |
| CODE-4 (validate all untrusted input) | Yes | Statement CSV/PDF, quick entry, Wallet text, notification text, backup JSON, FX JSON, deep links, Worker replies. MASTG 0370, 0395. |
| RESILIENCE-1 to 4 (anti-tamper, jailbreak, obfuscation) | Skip | No server-held money, no secrets in the app, free app. Only two cheap checks: no debug flags in Release and no `get-task-allow` (MASTG 0084, 0261). |
| PRIVACY-1 (minimise access) | Yes | Only camera permission string (`project.pbxproj:376-377`). Entitlements all used: iCloud, Sign in with Apple, App Attest, app group. MASTG 0360, 0362. |
| PRIVACY-2 (no identification) | Yes | Analytics id and Sentry user are the salted hash only; no IP, no screenshot (`CrashReporting.swift:80-90`). |
| PRIVACY-3 (transparency) | Yes | What leaves the phone must match the privacy page, `PrivacyInfo.xcprivacy` and the App Privacy label. Fix `[S-10]` wording. |
| PRIVACY-4 (user control) | Yes | Consent switch off means no requests. Default off in EU, UK, Switzerland. Delete Account removes the PostHog person. |

### A1.2 Lines to try

- `[M:STORAGE-1]` Run the app with sample data. Dump the data container (`xcrun simctl get_app_container $U com.kameshraj.spend data`). `grep -r` for a distinctive merchant (e.g. `ZEBRACAFE`) in `Library/Preferences`, `Library/Caches`, `tmp`, `Library/Application Support`. Only the SwiftData store may hold it. UserDefaults and Caches must not.
- `[M:STORAGE-1]` Same grep in the app group container (`... groups`). Only the widget summary may hold shop names. Look at `[S-03]`: read the file and say which fields it holds, and whether the "hide when locked" setting still leaves names on disk.
- `[M:STORAGE-1]` `Keychain.set` uses `AfterFirstUnlockThisDeviceOnly` (`Keychain.swift:25`). Log in with Google, read the item class with a Keychain dump (MASTG-TEST-0302 shows how [2]). Pass: not `Always`.
- `[M:STORAGE-1]` Export a CSV. Check the file has complete file protection (`Exports.swift:19-22`). Check the temp file is deleted after the share sheet closes.
- `[M:STORAGE-2]` Stream logs during a full session: `xcrun simctl spawn $U log stream --level debug --predicate 'subsystem == "com.kameshraj.spend"'`. Log a tap `ZEBRACAFE 12.34`, scan a receipt, import a CSV. Pass: no merchant, amount, email or token in any line, in a Release build. (Debug hook at `SpendApp.swift:163-168` prints text with `privacy: .public` and must be Debug-only.)
- `[M:STORAGE-2]` Release binary: `strings Spend.app/Spend | grep -E 'SPEND_(DEMO|TAP|REEL|OLD|ACTIVITY|FOUNDER)'`. Pass: none. [MASVS-RESILIENCE, MASTG-0084]
- `[M:STORAGE-2]` Pasteboard: copy a purchase amount in the app; read `xcrun simctl pbpaste $U`. Pass: the app copies only the support email (`HelpFeedbackSettingsView.swift:92`, `FounderNoteSheet.swift:136`). Nothing else on the pasteboard.
- `[M:STORAGE-2]` Keyboard cache (MASTG-0055 [2]): type `ZEBRACAFE` in the merchant field, then in another app's field type `ZEB`. Pass: no suggestion from Sortd. Check the field autocorrect setting.
- `[M:STORAGE-2]` Third parties: install a proxy root cert with `xcrun simctl keychain $U add-root-cert <mitm-ca.pem>`, run mitmproxy, use every feature with consent ON. Pass: PostHog and Sentry payloads hold no merchant, amount, note, email. With consent OFF: no PostHog or Sentry request at all (PostHog opt-out, `CrashReporting.consentChanged` closes Sentry).
- `[M:PRIVACY-4]` Consent default: set the simulator region to GB, FR, CH (`-AppleLocale en_GB`, `fr_FR`, `de_CH`) on a clean install. Pass: switch starts OFF. Region AU, SG, US: ON (`Analytics.defaultConsent(regionCode:)`, `Analytics.swift:391`).
- `[M:PRIVACY-4]` With consent on in a TestFlight build, replay is compiled in (`SORTD_REPLAY` in Release, `[S-10]`). Turn the switch off mid-session. Pass: no replay upload after that. Amounts, shop and note fields are masked in a recorded session (ask for one test session in PostHog).
- `[M:CRYPTO-1]` Back up twice with no change. The two CloudKit blobs differ (fresh nonce). Flip one byte of a saved blob and restore: "can't be read" (`CloudBackupError.corrupt`), no crash, nothing half-imported.
- `[M:CRYPTO-2]` The backup record holds no key. Backup with iCloud Keychain OFF: key stays local; restore on a second simulator gives `noKey` message, and no new key is made while a backup exists (`CloudBackup.swift:36-39`).
- `[M:AUTH-1]` Worker (curl, section B): no `X-Attest-*` headers → 401 `attest_missing`; a request with an `Origin` header → 403; body of 5 KB → 413; GET → 405; unknown path → 404; 11 calls in 60 s from one IP → 429 with `Retry-After`. Prod ignores `X-Sortd-Debug` even with a valid dev token (`handler.ts:111-119`). Replay the same attested headers and body within 120 s: README says the Worker keeps no copy, so a replay is likely accepted; the action is idempotent, so note it, do not panic (not verified).
- `[M:AUTH-2]` App Lock with Face ID failing 3 times → passcode fallback works. Cancel the sheet → stays locked and offers a retry. Remove the passcode while the lock is on → app opens and the lock switches off (`AppLock.swift:217-219`, from 22 Sep G4).
- `[M:AUTH-3]` Delete Account asks for a fresh Apple sign-in (code must be fresh), and a repeat tap does not send two revokes.
- `[M:PLATFORM-3]` App switcher: with App Lock ON and OFF, press Home, open the switcher. Pass: the Sortd card shows the cover, not amounts (`SpendApp.swift:288-289`). Repeat after a system alert (camera permission) and after opening Control Centre. Screenshot each.
- `[M:PLATFORM-3]` Lock Screen widget and the "Logged" notification (`4f32cba`) while the phone is locked: amount and shop hidden when "hide when locked" is on (`SortdWidget.swift:414`, `WidgetBridge.swift:145`). Phone only.
- `[M:CODE-3]` `Package.resolved` versions of posthog-ios and sentry-cocoa against their latest releases and security pages. Write the versions in the report.
- `[M:CODE-4]` Backup file from a newer version with an unknown field, a negative amount, a 2 GB-string merchant: clear error or ignore, no crash, no half import (see also `data-backup` in attacks.md).
- `[M:RESILIENCE]` `codesign -d --entitlements :- <Release .app>`: no `get-task-allow` in the TestFlight or archive build (MASTG-TEST-0261 [2]).
- `[M:PRIVACY-1]` Open every screen with all permissions denied (`xcrun simctl privacy $U revoke all com.kameshraj.spend`). No crash; camera screen explains and offers Settings.

## A2. crash-and-stress

Real-world patterns come from Apple forum threads. SwiftData has crashed in the field on: a leaked `ModelActor` after logout [8], migration with leftover `@Attribute(originalName:)` [9], disk full when saving (SQLite error 13) [10], and a store that fails to open when CloudKit storage is full [10]. Sortd uses `cloudKitDatabase: .none` (`SpendStore.swift:44`), so the CloudKit-mirror ones do not apply, but the others can.

- Kill during save: log a purchase with `SPEND_TAP_REPEAT` (Debug) and run `xcrun simctl terminate $U com.kameshraj.spend` at random moments in a loop of 100. Relaunch each time. Pass: opens every time, no duplicate, no half row. [R]
- Kill during import (2,000 rows), during Back Up Now, during Restore, during Delete All Data. Relaunch. Pass: either all or nothing; Delete All Data finishes at next launch (`CloudBackup.deletePendingKey`).
- Low storage: fill the simulator disk (`mkfile` into the data container until 50 MB free) then log a purchase, import, back up. Pass: "save failed" alert (`saveFailedAlert`), no crash, no silent loss. Launch at 0 bytes free: `[S-02]` decide what should happen.
- Corrupt store: stop the app, truncate `default.store` to 4 KB, launch. Observe `SpendStore.swift:52`. Record whether the user sees anything useful. `[S-02]`
- Old store, new build: install build N, add 200 rows, install build N+1 over it (`xcrun simctl install` without uninstall). Pass: rows intact. Repeat from a store made on the previous TestFlight build once there is one. `SpendMigrationPlan` has no stages yet.
- Time zone: log at 23:59 in `Asia/Singapore`, then set the simulator to `Australia/Sydney` and `America/Los_Angeles`. Pass: purchase stays on its day (also in attacks.md); month totals do not move.
- DST: tap at 02:30 on Sydney's October DST day (also in attacks.md); day total and Activity list agree.
- Date set to 2030 then back; set to 2001 then back. Pass: no crash, "Today" correct, nothing logged into 2030 stays hidden. Budget pace (`Pace.swift`) at day 0 and day 31: no divide by zero.
- Calendar: launch with `-AppleLocale th_TH@calendar=buddhist`, then `ja_JP@calendar=japanese`, `ar_SA@calendar=islamic-umalqura`. Log a USD purchase and import a statement. Pass: dates, FX request URL and `FXRate` keys use Gregorian year 2026 (`[S-01]`); month headers do not say 2569.
- Number formats: `-AppleLocale ar_EG` (Arabic digits), `hi_IN@numbers=deva`, `de_DE` (comma decimals), `fr_FR` (narrow no-break space), `de_CH` (apostrophe). Add a purchase by typing, by quick entry, by statement, by Shortcut. Pass: same amount in each; `AmountEntry` accepts what the keyboard gives.
- Clock: 12-hour vs 24-hour (Settings › General › Date & Time); time on a row, widget and notification reads right.
- 10,000+ rows: `SPEND_DEMO` is small; make a 10,000-row CSV (script in A6) and import. Open Activity, Insights, Search, widget refresh, backup, restore. Pass: numbers in A8; no hang over 250 ms on the main thread (Hangs instrument).
- Memory warning: Simulator › Debug › Simulate Memory Warning while on Insights with 10,000 rows. Pass: no crash, screen redraws.
- Interrupts: incoming call (Simulator has no call; use a Control Centre pull, a notification banner, Siri, a share sheet) during the Add sheet, Face ID, import. Pass: half-typed purchase is kept (`3cd4398`) and no double save.
- Background and return after 1 hour / next day; after Low Power Mode on; after the phone is rebooted. Widget and "Today" correct.
- iCloud signed out mid-session: Settings › Apple ID sign out (device), or `xcrun simctl icloud_sync` after change. Pass: backup shows `notSignedIn` message (`CloudBackupError.notSignedIn`), app data untouched, turning it back on does not overwrite an existing backup without "Restore first" (`restoreFirst`). Listen for account change (`CKAccountChanged`) [17].
- iCloud account switched (A to B) while the switch is on: the app must not upload A's data into B's private database, and must not delete A's backup. Observe both cloud copies.
- iCloud Keychain off, then back on: A1 (CRYPTO-2) line; message not stuck forever.
- Airplane mode and Network Link Conditioner "100% Loss", "Very Bad Network" during FX fetch, sign-in, backup, restore, Worker delete. Mac NLC affects the whole Mac, not only the simulator [16]; on the phone use Settings › Developer › Network Link Conditioner. Pass: spinner stops by its timeout (FX 15 s `FXService.swift:248`, Worker 20 s `AccountStore.swift:538`), message in plain words, retry works.
- Zombie and memory scribble run: `SIMCTL_CHILD_MallocScribble=1 SIMCTL_CHILD_MallocGuardEdges=1 xcrun simctl launch --checked-allocations $U com.kameshraj.spend`, then do a normal session (B).

## A3. deep-links-and-intents

Handler: `Router.open` and `Router.target(for:)` (`Router.swift:57-90`), `.onOpenURL` (`SpendApp.swift:376`). Known names: `purchase`, `add`, `scan`, `budget`, `activity`, `insights`, `bills`, `import`; anything else opens Home. Try every line with `xcrun simctl openurl $U '<url>'`. Test on a finished-setup install; links are ignored while setup is open (`Router.swift:61`).

- `sortd://activity` → Activity tab.
- `sortd://purchase/<valid uuid of an existing row>` → Activity opens that row.
- `sortd://purchase/<valid uuid, row deleted>` → Activity tab, nothing opens, no error.
- `sortd://purchase/not-a-uuid`, `sortd://purchase/`, `sortd://purchase//`, `sortd://purchase/../../x` → Activity tab, no crash.
- `sortd://purchase/<uuid>?x=1#frag`, `sortd://purchase/<uuid>/extra/parts` → same row (query ignored), no crash.
- `sortd://` (empty), `sortd:`, `sortd:///`, `sortd://%00`, `sortd://ACTIVITY` (upper case), `sortd://activity%20` → Home (or Activity for case); no crash. Note which.
- `sortd://add?amount=9999999&merchant=<script>` → Add sheet opens empty; the query values are ignored (the router reads none). Pass: nothing pre-filled, nothing saved.
- A 10,000-character host and a 10,000-character id → no crash, returns under 100 ms.
- `sortd://bills` and `sortd://import` while Settings is open, and `sortd://activity` while Settings is open (waits 450 ms, `Router.swift:67-74`) → right screen, no stuck sheet. Send 5 links in a row 100 ms apart.
- Link while App Lock is locked → lock screen stays; the cover hides the target; after unlock the target shows. Nothing visible before unlock. `[S-07]`
- Link while the Add sheet has a half-typed purchase → typed text is not lost.
- Link sent from Safari on the simulator (a web page with `<a href="sortd://delete">`) → no prompt that deletes; unknown name goes Home. Pass: no deep link can change data.
- Shortcut text `LogWalletTapIntent` with 10,000 characters, with only emoji, with RTL, with embedded newlines and tabs, with `A$` and no digits, with 50 amounts → logged once or refused; never a crash; "Last Tap" says why (attacks.md has the base cases).
- iOS 27 notification route (`SPEND_TAP_NTITLE`, `_NSUBTITLE`, `_NBODY`, Debug): empty title, 4 KB body, body with two amounts, body from a non-Wallet app, the same notification twice (dedupe, `ApplePayOnlineDedupeTests` exists) → one row, right shop, or "needs a look".
- `LogPurchaseIntent` with nil card, nil merchant, amount `0`, `-1`, `1e30`, `NaN` → Siri error text, no crash, nothing saved.
- Two intents at the same instant while the app is launching and the phone is locked after reboot (A5, Raj-only) → both go to `TapQueue` if the store is not readable, and drain at next launch.
- Widget tap on each widget size (small, medium, large, Lock Screen) → right target (`widgets-four` `[R]`). Widget showing a deleted purchase → opens Activity quietly.
- Siri question intents (`SpendQuestionIntents.swift`) for a month with 0 purchases and with 10,000 → spoken answer, no divide by zero.

## A4. account-sync-safety

Replaces `gmail-security`. Parts: Sign in with Apple, Continue with Google (identity only, PKCE), Sign Out, Delete Account (Worker), iCloud backup and restore, App Lock, crash and error reporting, offline.

- Sign in with Apple, then Sign Out: purchases untouched; Keychain Google token gone; analytics id cleared (`Analytics.swift:365`).
- Hide My Email choice and no-name choice (Apple only returns the name the first time): app shows something sensible, no crash on missing email.
- Revoke Sortd in Settings › Apple ID › Sign in with Apple while the app is open → next launch signs out, says why, keeps purchases (`AccountStore.swift:293`).
- Continue with Google: cancel the web sheet, deny consent, close the sheet mid-way, rotate or lock the phone during it → back to Settings, no spinner stuck. Scope asked is identity only; no Gmail scope on the consent screen `[R]` (Gmail removal).
- A stored old Gmail token under the Keychain service (put a fake item with `security` or a Debug build) → `GmailCleanup` removes it, no crash `[R]`.
- Delete Account with network: Apple revoke 204, PostHog delete 204, local sign-in data cleared. Purchases kept unless the user chose to delete them. Two taps on the button → one run (`905ead8` buttons lock `[R]`).
- Delete Account offline: jobs queue (`3f850cd` `[R]`); go online → queue drains once; kill the app between → still drains. Dev Worker needed on the simulator (App Attest does not work there; README dev bypass).
- Delete Account with Worker returning 429, 502 `apple_invalid_grant`, 503, timeout (point `ACCOUNT_WORKER_URL` at a local stub) → plain message; Apple manual steps shown for 502; no retry loop.
- Delete Account from a TestFlight build against the prod Worker: one real run with a throwaway Apple ID. This is the only way to prove production App Attest works (`[S-04]`).
- Backup ON → add 3 purchases → close the app → CloudKit record updated within the 10-minute gap and 5-second debounce (`CloudBackup.minimumGap`, `.debounce`). Use `Back Up Now` twice fast → one backup (`[R]` lock while working).
- Restore on the same phone twice → no new rows the second time. Restore on a second phone with the same Apple ID and iCloud Keychain ON → all rows. With iCloud Keychain OFF → `noKey` message, retry later works.
- New phone that already has a backup but never backed up (`restoreFirst`): turning the switch on must not overwrite it.
- Delete All Data with iCloud ON and offline → local data goes, iCloud delete queued (`deletePendingKey`); a new backup made after the queue time is left alone (`deleteQueuedAtKey`). Go online → old copy removed.
- Delete All Data, then reinstall: onboarding starts clean; the backup key survives on purpose (`KeychainBackupKeyStore` comment); the old Google token does not `[S-11]`.
- iCloud full (`quotaExceeded`) and rate limited (`rateLimited`) → "Backup is paused" text, no retry loop, no crash.
- Sentry: in a Release or TestFlight build with consent ON, use Developer › Send test report and one forced crash (`DeveloperMenuView.swift:133`). In Sentry: stack, device, OS, version; no message, no breadcrumbs, no screenshot, no IP, user is the hash only (`CrashReporting.scrub`). With consent OFF: crash again; nothing arrives.
- ErrorLog: force three failures (read-only import file, full disk, Worker 503). Developer › Recent errors shows type and place; no merchant (`[S-06]`).
- App Lock + backup: restore while locked in the background → no data shown on lock screen; unlock works after restore.
- Offline for a day: add purchases, import a statement with a foreign currency → rows saved with a "rate pending" state, converted when online (`Connectivity.catchUp`, `50a33c2` `[R]`); totals do not change after, by more than the FX move.

## A5. onboarding-and-applepay

- Clean install, no sample data, tap through every setup step at normal speed, then at double speed, then double-tap each button (`setupClosedAt` guard exists, `SpendApp.swift:262`). Pass: one action each, no skipped step, no tab tapped underneath.
- Kill the app on every setup step and relaunch → resumes or restarts cleanly; progress bar does not jump (22 Sep U8).
- Deny notifications, allow notifications, allow then turn off in Settings later → Budget Pace Alert reads "off" (`93aa2c0` `[R]`); no stuck toggle.
- "Explore with sample data" then Clear → setup opens at once; privacy cover and App Lock still work (22 Sep U2 `[B]`).
- "Run Setup Again" from Settings with 500 rows → data untouched; cover and lock active.
- Home currency AUD, SGD, JPY (no cents), KRW, USD at first run; change it later → totals converted once, budget converted once (`[B]` from 22 Sep D1/D2, and D2 of 26 Sep merge restore).
- Shortcuts automation setup on iOS 27: the "Notification" trigger and its setup words show on iOS 27 only (`SetupGuideView.swift:20`, `WalletSetupGuide.swift:259`). On iOS 26 the guide shows only the older "Transaction" route. Check both versions (A7).
- Apple Pay card tap (Raj): shop, amount, card appear within a minute; "Logged" notification appears (`4f32cba`); Last Tap text shows. Two taps at once → two rows. Same tap twice by the Shortcuts retry → one row.
- Online Apple Pay payment (Raj): in-app and website payment gives a Wallet notification; the notification route logs it once; if the shop name is a payment processor, the row is flagged, not wrong.
- Apple Pay refund and reversal (Raj, optional): a refund notification lowers the total once; a partial refund lowers it by the refund amount (`[B]` U1 from 26 Sep).
- Shortcut run while the phone is locked right after a reboot, before first unlock (Raj): store may not be readable; tap goes to `TapQueue`, appears after unlock; nothing lost. (`SpendStore.containerForIntent`.)
- Shortcut run in Low Power Mode, with Focus on, with Airplane mode → logs offline; FX filled later.
- Wallet card removed or renamed after setup → rows keep the old card name; unknown card shows a clear label (`ApplePayHuntGarbageCardTests`).
- Setup health check (`ApplePayHealthCheck.timeout` 20 s): no tap seen in 20 s → message explains what to do; does not claim success.
- Scan a receipt (Raj's hands for camera): clear receipt, blurry, upside down, in Thai or Japanese, 2 receipts in one frame, a screen photo. Pass: amount right or a clear "couldn't read"; photo not saved (camera text says so).
- First purchase celebration and tips (`TipState`) do not cover the month total (`729ffc6`).

## A6. input-and-monkey

Inputs and fuzz sets from the coordinator's r/softwaretesting list, made Sortd-specific. Corpora: `blns.json` from big-list-of-naughty-strings (MIT licence) [11], SecLists `Fuzzing/` (Unicode, special chars, big numbers) [12], csv-spectrum CSV edge cases [13], PDF.js test PDFs including fuzzed and malformed files (Apache 2.0) [14].

### Input limits (every text field)
Fields: shop, note, card name, category name, budget, category limit, search, quick entry, Add amount, import text box, feedback box.
- Paste 10,000 characters into each text field → accepted and truncated, or refused with a message; the list row truncates with an ellipsis; the amount is never cut; no hang over 250 ms.
- Paste each line of `blns.json` into shop, note and card name (script via `xcrun simctl pbcopy`) → saved as typed (not executed, not trimmed to empty), shows in Activity, Search finds it, CSV export quotes it, backup round trip keeps it.
- Emoji with ZWJ (`👩‍🍳`), flags, skin tones, zero-width space `U+200B`, RTL override `U+202E`, a combining-mark pile `Z͑ͫ̓ͪ̂ͫ̽͏̴̙̤̞͉͚̯̞̠͍A̴̵̜̰͔ͫ͗͢L̠ͨͧͩ͘G̴̻͈͍͔̹̑͗̎̅͛́Ǫ̵̹̻̝̳͂̌̌͘`, a name of only spaces, a name with a newline → no crash, no layout break at AX5, de-duplication treats them as written.
- Numeric fields: `abc`, `` (empty), `-5`, `0`, `0.00`, `"5"` (with quotes), `5e3`, `1e400`, `NaN`, `Infinity`, `９９`, `٥٫٠٠`, `1,2,3`, `1..2`, `999999999999999999999.99` → refused or parsed right; never a crash; the Save button says why it is off.
- Budget `0`: Pace, daily average, percent-of-budget, progress ring all handle zero (no `NaN%`, no divide by zero; `Pace.projectedOverDay` takes `Double`, `Pace.swift:17`). Category limit `0` and negative: same. Budget smaller than what is already spent → "over" state, no negative ring.
- Budget exactly equal to spent; one cent under; one cent over → "on budget" and "over" flip at the right cent.
- Search: 5,000 characters, a regex-looking string `(.*)+`, `%`, `\`, an emoji, a single RTL char → returns quickly, no crash.
- Quick entry: `rent 1,200`, `laptop 1,299`, `coffee 4,5`, `5 coffees 20`, `20 dollars coffee`, `coffee $20 and tea $5` → one clear result or a question, never `$9` (`[B]` M7).

### Fenceposts and dates
- Purchase at `00:00:00` and `23:59:59` on the last day of a month, the first day, 29 Feb 2028, 31 Dec to 1 Jan, DST changeover hour (Sydney first Sunday of October, Singapore has no DST) → right day, right month. Day totals add up to the month total to the cent (check with 50 mixed purchases; script it).
- Day Pager (`DayPager.swift`): go to a date before the oldest purchase, after today, to a day with 0 rows, forward and back 400 times → no crash, "Today" button returns.
- Date pickers in Add and Insights ranges: start after end → refused or swapped, with a message; one-day range includes both ends; "this month" at 00:00 on day 1.
- Month totals on 31 Jan, 28 Feb, 29 Feb, 30 Apr: the pace line uses the right days in month.
- Subscriptions and bills (`Recurring.swift`): monthly bill on the 31st in a 30-day month and on 29 Feb; reminder fires the day before (`Reminders.swift`).

### Money maths
- Every money value is `Decimal` in the model (`Transaction.swift:20,24,126,220`), but `Pace.swift:17`, `FXService.swift:8,92,273` use `Double` for settings and rates. Check: converting 100 purchases at 3 rates; sum of rows in home currency equals the month total shown, to the cent. Rounding mode `.plain` (the `Decimal.rounded` extension at the end of `FXService.swift`); JPY/KRW 0 places, KWD/BHD 3 places (if supported).
- Convert A$4.50 to SGD to AUD → back to the same number, or the app keeps the original and converts once.
- Mixed currencies: 20 rows in 5 currencies; change home currency and back → totals return to the same value; no drift.
- Refund of a purchase made in another currency at another rate → total lowers by the original amount, once (`Refunds.swift`).

### "Does not do what it should not"
- A deleted row is not in Home, Insights, widgets, search, backup, CSV export, Siri answers, budget pace. Check each (also an undone delete, `PendingDeletes.swift`).
- Hidden or test rows (sample data, `DemoData`) are not counted once cleared.
- Transfers and card payments in a statement are excluded (credit card bill line) (`[B]` S2).
- A refund is not counted twice (tap + statement + notification of the same refund).

### File import
- `statement.csv` that is a renamed JPG, renamed ZIP, renamed PDF; a `.pdf` that is a CSV; an empty file (0 bytes); a file of only a BOM; a 50 MB CSV; 200,000 rows; a UTF-16 CSV; a file with `\r` only line breaks; BOM + CRLF + `;` separator; quoted comma `"SMITH, JOHN & CO"`; a quoted newline inside a cell; unbalanced quote; 5,000 columns; a header only. Use csv-spectrum files as the base [13]. Pass: clear error or correct parse, no crash, no memory over 300 MB.
- PDFs: encrypted PDF, password PDF, scanned image-only PDF, 500 pages, 0 pages, truncated at 50%, PDF with a loop in object references; PDF.js `*-fuzzed.pdf` samples [14]. Pass: error message in plain words; memory and time bounded; cancel works.
- Backup file: truncated, empty, newer version, same row id twice, row with year 9999, amount `1e999` (also in attacks.md `data-backup`).
- Import the same file twice, and with two clicks on Import → one set of rows (`905ead8` `[R]`).
- Deep links with junk: see A3.
- Files app: open a `.csv` from Files with "Open in Sortd" if the app registers a document type (check `Spend-Info.plist`: none registered; only the in-app picker).

### Spam-click and interrupts
- Double and triple tap: Save (Add), Delete, Undo, Restore, Back Up Now, Import, Sign in with Apple, Continue with Google, Delete Account, Delete All Data confirm, Run Setup Again, tip buttons. Pass: one action each; button locks while work runs (`905ead8` `[R]`).
- Tap Save then immediately swipe back, tap Home, rotate (portrait only: `UISupportedInterfaceOrientations_iPhone = Portrait`), or lock the phone → one row, no crash.
- Kill the app or switch Airplane mode on during: save, import, backup, restore, sign-in, Delete Account → see A2 and A4; pass is the same: all or nothing.
- Timeouts: point FX at a stub that waits 60 s (`mitmproxy` or `python -m http.server` with sleep) → spinner ends by 15 s, rate shown as "pending", next launch retries; CloudKit slow (NLC "100% loss"); Worker slow (20 s).

### Minesweeper (neighbours of past bugs)
For each fixed bug in `docs/BugHunt-2026-09-22.md` and `BugHunt-2026-09-26.md`, test the neighbour, not the same input:
- M2 baht/peso/won/yuan markers: try `₹`, `₪`, `₺`, `₴`, `₦`, `R$`, `kr`, `zł`, `Rp`, `RM` with a space, `HK$`, `NT$`, `A$` with a thin space; and amounts written with markers after the number (`350฿`).
- M3 narrow-space and apostrophe thousands: also `1 234,56` with a normal space, `1.234.567,89`, `1,23,456.00` (Indian grouping), `1٬234٫56` (Arabic separators).
- M1 refund words in shop names: `REFUND` at the start; `CREDIT UNION`; `REVERSAL TAVERN`; `RETURNS DEPOT`.
- S1 CRLF: also `\r` only, `\n\r`, mixed endings in one file, a final line without a line break.
- S5 quoted commas in the first ten lines: also quoted commas only in line 11, 5000.
- D1/D3/S6 dedupe: purchases 2 s, 5 min, 11 min, 2 days, 3 days apart, same amount, same shop, different cards and different sources.
- G1 App Lock after `.inactive`: check 15-minute and 1-hour grace after a call banner, a Face ID cancel, a Control Centre pull.
- U2/U3 widget refresh: after changing budget, category limit, currency, card name, restore, import, Delete All Data, midnight, a time zone change.

### Monkey test (random taps, swipes, text)
There is no tap command in `simctl` (the subcommand list from `xcrun simctl help` has none). Three ways:
1. **XCUITest random driver (recommended, no extra tools).** The repo has only a unit-test target `SpendTests` (no UI test target seen; add one on a branch). One test, seeded: loop 400 steps; each step picks one of: tap a random hittable element from `app.descendants(matching: .any)`, tap a random coordinate, swipe up/down/left/right, long press, type a random line from `blns.json` into the focused field, rotate nothing (portrait only), `XCUIDevice.shared.press(.home)` then `app.activate()` every 50 steps. Print the seed and step number. After each step assert `app.state == .runningForeground`; if not, fail and keep the seed. Skip labels that match `Delete All Data|Delete Account|Sign Out|Erase|Reset` and anything that opens another app (Settings, Safari, Mail); re-activate after those. Launch with `SPEND_DEMO=1` and also once with no data. Run: `xcodebuild test -scheme Spend -destination "id=$U" -only-testing:SortdUITests/MonkeyTests -enableAddressSanitizer YES`.
2. **xcmonkey** (open source, drives the simulator through iOS Development Bridge; taps, swipes, presses, blind or element-aware) [15]. Needs `idb`; not verified that it works with the iOS 27 simulator.
3. **SwiftMonkey** (Zalando, runs inside XCUITest, with a visual overlay of the taps) [15]. Old; not verified on Xcode 27.
Watch for: process crash (`~/Library/Logs/DiagnosticReports/*.ips`, usual place; not verified in the sources), hangs (record with `xctrace --instrument Hangs`, B), memory growth (Allocations), console errors from `subsystem == "com.kameshraj.spend"`. Run 3 seeds. A pass is 3 seeds of 400 steps with no crash and no hang over 2 s.

### First-time-user eyes
One pass, no sample data, no knowledge of the app: see C2.

## A7. compatibility-ios26-and-sizes

Facts from the repo and this Mac: deployment target `IPHONEOS_DEPLOYMENT_TARGET = 26.0` (`project.pbxproj:326`); `TARGETED_DEVICE_FAMILY = 1` (iPhone only) in every target (`:396,435,454,474,503,532`); only the iOS 27.0 runtime is installed, and `simctl list runtimes` lists an iOS 26.4 runtime as unavailable; the only device is "iPhone 18 Pro". `scripts/sim.sh` clones from "iPhone 18 Pro" on iOS 27 (`sim.sh` header).

- Get an iOS 26 runtime: `xcodebuild -downloadPlatform iOS -buildVersion 26.4` (flag from `xcodebuild -help`; the exact build number is a guess, not verified) or Xcode › Settings › Components. About 8 GB. Per the disk rule in `CLAUDE.md` delete the simulator when done.
- Create devices: `xcrun simctl create SortdSE com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation <runtime-id>` (smallest screen; if the iOS 27 runtime refuses it, use "iPhone 17e" or "iPhone 16e"), `...iPhone-17-Pro`, `...iPhone-17-Pro-Max` on both runtimes. Raj's phone is an iPhone 17 Pro.
- iOS 26 smoke test, every tab: Home, Activity, Insights, Search, Settings sheet. Onboarding, add a purchase, edit, delete, import a CSV, Back Up Now (iCloud may not work on a fresh simulator; use `xcrun simctl icloud_sync`), widgets add and refresh, dark mode, AX5.
- iOS 27-only features must hide on 26: (1) the Wallet Notification trigger and its setup words (`SetupGuideView.swift:20` `#available(iOS 27.0, *)`; `WalletSetupGuide.swift:259`); (2) the prominent search tab (`SpendApp.swift:547-551`, `#if compiler(>=6.4)` and `#available(iOS 27, *)`; on 26 the same slot as a search circle, `NavLayout.swift:18`); (3) `LogWalletTapIntent` notification parameters (`LogWalletTapIntent.swift:124`) must not show a broken option on 26. Pass: no empty rows, no "iOS 27" text on 26, no crash.
- StoreKit tests fail on 26.x simulators for no code reason (`CLAUDE.md` Build/test; HANDOVER.md): run `scripts/test.sh` without `--storekit` and do not count TipJar tests.
- Sizes: SE-class (4.7" if it boots), Pro (6.3"), Pro Max (6.9"): clipping at AX5, the floating Home and + buttons over the last row (`[B]` U4 from 26 Sep), Add sheet keyboard cover, widgets in each family. Use `scripts/sim.sh textsize ax5` and `scripts/sim.sh appearance dark`.
- iPad: the app is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`), so on an iPad it runs in the iPhone-app compatibility mode, if Apple still offers it for iOS 26/27 (not verified; also check the App Store Connect "iPad availability" for the app). One run on an iPad simulator: launch, onboarding, add a purchase, rotate; Pass: no crash, usable. Decide: allow or block iPad in App Store Connect.
- Increase Contrast: `xcrun simctl ui $U increase_contrast enabled`. Reduce Motion, VoiceOver labels via `ui-driver`.

## A8. performance

Numbers are proposed pass marks (mine), not Apple rules; I did not verify an official number. Hit them on the phone (iPhone 17 Pro) for the final figures; the simulator is for finding slow code, not for the final number. The app already has timing marks: `Perf.swift` (signposts, subsystem `com.kameshraj.spend`, category `perf`, "launch to first frame", `fx.fetch`), and a benchmark `SpendTests/StatementSpeedBenchmark.swift` (`TEST_RUNNER_SPEND_BENCH=1 scripts/test.sh --only StatementSpeedBenchmark`).

| Metric | Pass mark (proposed) | How to measure |
|---|---|---|
| Cold launch to first frame, empty store | 1.0 s or less on phone | `Perf` log: `log stream --level debug --predicate 'subsystem == "com.kameshraj.spend" && category == "perf"'`; or `xctrace` template "App Launch" |
| Cold launch with 10,000 rows | 1.5 s or less | same; build the store with the CSV script (A6) |
| Time from launch to first Activity row on screen | 2.0 s or less with 10,000 rows | `xctrace` "Time Profiler" or "SwiftUI" template, or a signpost at the first row's `onAppear` |
| Scroll Activity, 10,000 rows, fast flick for 10 s | no frame drops you can see; hitch ratio low | `xcrun xctrace record --template 'Animation Hitches' ...`; pass mark: under 5 ms of hitch per second (Apple guidance value from memory, not verified) |
| Statement import, 2,000 rows (CSV) | 10 s or less; UI never frozen over 250 ms | `StatementSpeedBenchmark` + `Hangs` instrument |
| Statement import, 2,000-row PDF | 30 s or less; cancel works | same |
| Backup, 10,000 rows | 10 s or less to write the blob (Wi-Fi) | `Perf` span or timestamps in the unified log; note blob size (CloudKit asset, `CloudKitBackupStore.swift:28`) |
| Restore, 10,000 rows | 20 s or less; no duplicate rows | same, then check row count and the month totals |
| Insights and Home with 10,000 rows | open in 1 s or less | Time Profiler |
| Memory, normal session | stays under 150 MB, no steady growth after 20 tab switches | `Allocations` template; Xcode debug gauge |
| Memory, 50 MB CSV | under 400 MB peak, no crash | Allocations |
| Main thread hangs | none over 250 ms in a 10-minute session (hang threshold: proposed) | `Hangs` instrument |
| Battery and background | no work while backgrounded beyond one backup | MetricKit (iOS 27: `MetricManager` async reports; daily; simulator not verified) [5] |
| Widget refresh | updates within seconds after a change | add, edit, delete; see U2 `[B]` |

## A9. testflight-checks

- Clean device: an iPhone that never had Sortd (or erase the Keychain items by `Delete All Data`, delete app, reboot). Install the TestFlight build; first launch must not crash; first screen in under 3 s. Camera, notification, Face ID prompts show the right words.
- Crash-free first launch on both iOS 26 and iOS 27 phones if Raj has both; at minimum the simulator pair.
- Upgrade path: install build 1, add data, enable backup, App Lock, a widget; install build 2 from TestFlight over it. Pass: all data, settings, App Lock, widget, backup switch intact. `SpendMigrationPlan` has no stages yet; any model change in build 2 needs `SchemaV2` first.
- Restore to a new device: A4 steps with a second phone or an iPhone backup restore. Keychain `ThisDeviceOnly` items do not move (expected: Google sign-in gone, purchases back).
- Build expiry: TestFlight builds are available for up to 90 days [7]. Write the expiry date in the beta email. What does the app do on an expired build? (iOS shows its own message; nothing to test.)
- First external build goes to Beta App Review [7]; allow time; internal testers (up to 100) do not need to wait (the page says external testers need review; internal not verified).
- Feedback flow: screenshot in the app → TestFlight feedback → appears in App Store Connect [7]. Check Sortd's own "Help › Send feedback" mail link works and the support address `support@sortd.page` receives.
- Production App Attest: `[S-04]` Delete Account once from TestFlight against the prod Worker; check Worker logs for `status 204`, no `attest_invalid`.
- Sentry from TestFlight: Developer › "Send test report" and one forced crash; see them in Sentry (`docs/AppStoreChecklist.md` has the same step).
- Session replay is on in this build (consent on); verify masking once, and the beta text says so (`[S-10]`).
- `scripts/preflight.sh` passes; version and build bump; `ITSAppUsesNonExemptEncryption = NO` is set (`project.pbxproj:378`) — check this answer is right for AES-GCM backup (App Store export compliance question; not verified, ask Apple's page or a lawyer).

---

# Section B. Tool runs

Run one at a time on the iOS 27 simulator unless noted. Each sanitizer rebuilds the app, so use one build folder per run and clean it after (4.5 GB each, `CLAUDE.md` disk rule). `UDID=$(scripts/sim.sh boot)`. `PROJECT=Spend.xcodeproj`, scheme `Spend` (the only shared scheme).

Base command (from `scripts/test.sh`):
`xcodebuild -project Spend.xcodeproj -scheme Spend -destination "id=$UDID" -derivedDataPath .build/DD-<name> -resultBundlePath .build/<name>.xcresult -skip-testing:SpendTests/TipJarTests CODE_SIGNING_ALLOWED=NO <flags> test`

| Tool | Command or flag | Target | What a pass looks like | Time |
|---|---|---|---|---|
| Unit tests (CI mode) | `scripts/test.sh` | sim | Test run line shows all passed; no `✘` | 5 to 10 min |
| Known-bug tests | `scripts/test.sh --known-bugs` | sim | Every failure is a listed known bug; any new failure is a finding | 10 min |
| Address Sanitizer | base command + `-enableAddressSanitizer YES` (Apple's page lists this flag [4]) | sim; Apple says ASan also works on device | No "AddressSanitizer:" lines in the log. ASan does not find leaks or uninitialised memory [4]. Cost: 2 to 3x memory, 2 to 5x slower [4]. Most Swift code is memory-safe, so the value is in C code inside SQLite, Sentry and PostHog. | 20 min |
| Thread Sanitizer | base + `-enableThreadSanitizer YES` | **sim only**; Apple says it cannot run on a device [4] | No "ThreadSanitizer: data race". Last run 22 Sep: none. Re-run: Connectivity, ErrorLog, CloudBackup, TapQueue, widgets are new `[R]`. Cost: 5 to 10x memory, 2 to 20x slower [4]. | 30 min |
| Undefined Behavior Sanitizer | base + `-enableUndefinedBehaviorSanitizer YES` (flag shown in local `xcodebuild -help`) | sim | Apple says UBSan supports only C-based languages, not Swift [4], so expect nothing; run once for the C in dependencies. | 20 min |
| Main Thread Checker | On by default in dev schemes; for the Test action it is a value in the test plan [4]. No recompile; adds 1 to 2% CPU [4]. | sim and device (Apple's page does not limit it to the simulator; a summary I read said simulator-only, which I could not confirm) | No "Main Thread Checker: UI API called on a background thread" in the log during the monkey run | with other runs |
| Swift strict concurrency | `xcodebuild ... build SWIFT_STRICT_CONCURRENCY=complete` (used on 22 Sep) | sim | Count warnings; none in code touched by `[R]` commits. `SWIFT_VERSION = 5.0` in all targets (`project.pbxproj:395` etc.), so data-race problems are warnings, not errors. Optional one-off: `SWIFT_VERSION=6` to see how many become errors. | 15 min |
| Static analyzer | `xcodebuild ... analyze` (22 Sep used it) | sim | No new warnings vs 22 Sep (9 then) | 10 min |
| Malloc scribble, guard edges, checked allocations | `SIMCTL_CHILD_MallocScribble=1 SIMCTL_CHILD_MallocGuardEdges=1 xcrun simctl launch --checked-allocations $UDID com.kameshraj.spend` (`--checked-allocations` and `SIMCTL_CHILD_` from `simctl help launch`) | sim | A 20-minute session and the monkey run end with no `EXC_BAD_ACCESS` | 30 min |
| Zombie objects | Scheme env `NSZombieEnabled=YES`. Only helps with Objective-C objects; Sortd is Swift, so low value. | sim | no "message sent to deallocated instance" | skip unless a crash points to it |
| Instruments: Leaks | `xcrun xctrace record --template 'Leaks' --device $UDID --time-limit 120s --output .build/leaks.trace --launch -- com.kameshraj.spend` (xctrace flags confirmed in local `xctrace help record`) | sim | 20 tab switches, 5 Add sheets, 1 import, no leaked `Transaction` or view model after | 20 min |
| Instruments: Allocations | `--template 'Allocations'` same pattern | sim, then phone | Flat curve after tab switching; peak numbers for A8 | 20 min |
| Instruments: Time Profiler / CPU Profiler | `--template 'Time Profiler'` or `--instrument 'CPU Profiler'` (a third-party note says `--instrument` is more reliable on Xcode 26+ for export; not verified on 27) | sim and phone | no single main-thread function over 100 ms during launch, import, scroll | 30 min |
| Instruments: Hangs | `--instrument 'Hangs'` (listed by `xctrace list instruments`) | sim and phone | no hang over 250 ms (proposed mark) in the A8 flows | 20 min |
| Instruments: Animation Hitches | `--template 'Animation Hitches'` (listed) | phone best | Scroll 10,000 rows with a low hitch ratio | 15 min |
| Instruments: Data Persistence, Swift Concurrency, Network, SwiftUI | `--template 'Data Persistence'`, `'Swift Concurrency'`, `'Network'`, `'SwiftUI'` (all listed by `xctrace list templates`) | sim | Data Persistence: no fetch of all 10,000 rows on every Home refresh. Network: the hosts in A1 only. | 30 min |
| xctrace export | `xcrun xctrace export --input X.trace --toc` then `--xpath` (syntax from third-party notes; not verified) | any | numbers for the report | 10 min |
| App launch time | `xcrun xctrace record --template 'App Launch' ...` | phone | first-frame time within A8 mark | 10 min |
| Log watch | `xcrun simctl spawn $UDID log stream --level debug --predicate 'subsystem == "com.kameshraj.spend"'` | sim | no merchant, amount or token | during all |
| Network capture | mitmproxy on the Mac; `xcrun simctl keychain $UDID add-root-cert <ca.pem>`; set the Mac's proxy | sim | only hosts: api.frankfurter.dev, the Worker (`account.sortd.page`), PostHog EU, Sentry, Apple, Google, CloudKit; all TLS | 45 min |
| Worker tests | `cd worker && npm test` (vitest; 6 test files) and the curl list in A1 against the dev Worker | local, dev Worker | all pass; prod Worker ignores `X-Sortd-Debug` | 15 min |
| Network Link Conditioner | Mac: Additional Tools for Xcode, whole-Mac effect [16]. Phone: Settings › Developer › Network Link Conditioner [16] | sim (Mac-wide) and phone | A2 offline/slow lines recover | 30 min |
| simctl helpers | `simctl ui $U appearance dark`, `ui increase_contrast enabled`, `status_bar $U override --time 9:41`, `privacy $U revoke all <id>`, `push`, `openurl`, `pbcopy/pbpaste`, `location`, `io $U recordVideo f.mov`, `icloud_sync`, `keychain $U reset`, `get_app_container`, `install_app_data` (all in `xcrun simctl help`) | sim | used by A-sections | with runs |
| MetricKit | `MetricManager` reports daily and diagnostics at once on iOS 15+ [5]; does not run in the simulator as far as I could tell (not verified) | phone, TestFlight | Not a test now; plan to subscribe after launch or rely on Sentry + Xcode Organizer | later |
| Xcode Organizer crashes | Xcode › Window › Organizer › Crashes (TestFlight and App Store users who share diagnostics) | TestFlight | check after day 1 and day 3 | 10 min a day |
| Binary checks | `codesign -d --entitlements :- Spend.app`; `strings Spend.app/Spend | grep SPEND_` | Release build | no `get-task-allow`; no `SPEND_` debug names | 10 min |

Do not run ASan and TSan in the same build; run them one at a time (the guide I found says one at a time; not verified for Xcode 27).

---

# Section C. Phone run via iPhone Mirroring

Build to use: **a Release or TestFlight build.** `scripts/device.sh` builds Debug (`device.sh:19`), where Sentry is always off and its comment says Debug signs with app groups only `[S-05]`. Debug is fine for steps 1 to 40 (no iCloud, no sign-in); for steps 41 to 70 use TestFlight. iPhone Mirroring: Claude drives the mirrored screen from the Mac. Items marked **[RAJ]** need Raj's hands: Face ID or passcode prompts, camera, Apple Pay at a till, anything that opens Wallet, and typing the Apple ID password. Screenshot name pattern: `C<step>-<what>.png`. Keep a notes file open to write the time of each step.

### C1. Ordered script

| # | Action | Expected | Screenshot |
|---|---|---|---|
| 1 | Delete Sortd from the phone. Reboot. Install the TestFlight build. | Installs. Icon and name "Sortd" right. | home screen icon |
| 2 | Open it. Time first launch to first screen. | No crash; first screen under 3 s. | first screen |
| 3 | Onboarding: read each step; tap through; deny notifications at first. | Each step has one action; words plain; back works. | each step |
| 4 | Choose home currency AUD. Skip sign-in. Skip iCloud. | Lands on Home with a clear empty state (`95797d4`). | empty Home |
| 5 | Kill the app from the switcher on a setup step; reopen. | Resumes or restarts cleanly. | the step |
| 6 | Add a purchase by hand: shop `Test Cafe`, 4.50, Cash. | Row in Activity, Home total 4.50, widget not yet. | Add sheet, Activity |
| 7 | Add 3 more: one in USD, one `0.01`, one with an emoji shop. | Right rows; USD converted once; emoji kept. | Activity |
| 8 | Edit one, delete one, undo the delete. | One change each; totals right. | before and after |
| 9 | Double-tap Save on Add. | One row. | Activity |
| 10 | Quick entry: `lunch 12,50` then `rent 1,200`. | Both read right or ask. | result |
| 11 | Open Search; type `Test`, an emoji, a 200-character paste. | Fast; no crash. | results |
| 12 | Insights, each period, each chart; VoiceOver on one amount. | Numbers match Home; spoken "dollars" (`Money.spoken`). | Insights |
| 13 | Budget sheet: set 100, then 0, then 4.50 exactly, then 4.49. | No divide by zero; on/over flip at the cent. | each state |
| 14 | Category limit: same set. | Same. | each state |
| 15 | Cards: add a card, rename with 60 characters, delete it. | Name fits; rows keep their card label. | Cards |
| 16 | Subscriptions & bills: add a monthly bill due tomorrow. | Reminder is set (allow notifications now). | Bills |
| 17 | Import: CSV from Files (use a small bank CSV, then a file that is a renamed JPG, then an empty file). | Good file imports; bad files give a clear message. | each result |
| 18 | Import the same CSV twice. | No new rows the second time. | Activity |
| 19 | Import a PDF statement; cancel halfway once. | Rows right; cancel clean. | result |
| 20 | **[RAJ]** Receipt scan: one clear receipt, one blurry. | Amount right, or "couldn't read"; photo not saved. | scan, result |
| 21 | Settings › Cards & Appearance, Currency: change home to SGD, then back to AUD. | Totals convert once and return the same. | totals both |
| 22 | Settings › Purchase Sources › Apple Pay Logging: follow the pictures (iOS 27 route). | Steps match the screens; words say "Notification" on 27. | each step |
| 23 | Build the Shortcuts automation from the guide (Shortcuts app via mirroring). Turn off "Show When Run" and "Ask Before Running". | Automation saved. | Shortcuts list |
| 24 | **[RAJ]** One real Apple Pay tap in a shop (small, A$2 or more). | Row in Activity in under a minute; right shop, amount, card; "Logged" notification (`4f32cba`). | Activity, notification |
| 25 | Check Last Tap text on the Apple Pay page. | Shows the received text, no error. | the page |
| 26 | **[RAJ]** One online Apple Pay payment (website or app, small). | Wallet notification logs one row via the notification route. | row, notification |
| 27 | Run the same Shortcut by hand with 3 test texts (`A$5.00 TESTSHOP`, empty, 10,000 characters via Clipboard). | Row, nothing, nothing; no crash; Last Tap explains. | each result |
| 28 | Airplane mode: log a foreign-currency purchase; turn it off. | Row saved offline; rate filled after reconnect. | row before and after |
| 29 | Widgets: add small, medium, large, Lock Screen widget. Add a purchase; look. | Refresh in seconds. Lock Screen: amounts hidden while locked (if setting on). | each widget locked and unlocked |
| 30 | Tap each widget. | Opens the right place (`widgets-four`). | landing screen |
| 31 | Settings › Privacy: view the consent switch; turn off, on. | Default matches region (AU: on). | switch |
| 32 | Notifications: a bill reminder, a pace alert, a Logged notice. Look at them locked. | Text hides amount if "hide when locked" is on. | lock screen |
| 33 | Appearance: dark mode, AX5 Dynamic Type, Reduce Motion, Bold Text. Walk Home, Activity, Add, Settings. | No clipping; cross-fade not zoom with Reduce Motion. | one per mode |
| 34 | Interrupt: pull Control Centre, get a text, take a call (ask someone), during Add and Import. | Nothing lost. | before and after |
| 35 | Low Power Mode on, then off. | App fine. | none |
| 36 | Open the app switcher. | Cover shows (no amounts). | switcher |
| 37 | Time zone: set the phone to another zone and back. | Purchases stay on the same days. | Activity |
| 38 | Set Region to Thailand with Buddhist calendar; open Sortd; log a USD purchase. | Dates Gregorian-correct, rate fetched (`[S-01]`). Restore Region after. | dates, row |
| 39 | Set Region to Germany (comma decimals), then Egypt (Arabic digits). Enter 1,50 and ١٫٥٠. | Right amount or refused; no crash. Restore after. | field, row |
| 40 | Set the date forward one month, open, add, set back. | No crash; month change right. | Home |
| 41 | Settings › Account: Sign in with Apple. **[RAJ]** (Apple ID auth). | Signed in; email hidden choice works. | Account |
| 42 | Sign Out, then Continue with Google **[RAJ]**; only the identity scope shows. | No Gmail permission. Signed in, then out. | consent screen |
| 43 | Settings › Backup: turn on iCloud backup. | "Backed up" with time; no error. | status |
| 44 | Add 3 purchases; wait 15 minutes; Back Up Now twice quickly. | One backup; time updates. | status |
| 45 | Settings › Privacy & Security: App Lock on, "Immediately". **[RAJ]** Face ID. | Locks when leaving; unlocks with Face ID. | lock screen |
| 46 | **[RAJ]** Fail Face ID three times; use passcode. | Passcode fallback works. | prompt |
| 47 | App Lock "After 1 minute": leave 30 s, return; leave 90 s, return. | 30 s no lock; 90 s lock. | each |
| 48 | App Lock on, open `sortd://activity` link from Notes or Safari. | Lock stays; after unlock lands on Activity. | lock, Activity |
| 49 | Settings › Data: Export CSV; open in Files. | Opens right; commas and quotes in shop names fine. | CSV in Files |
| 50 | Settings › Data: Delete All Data (with backup on). | Local gone; setup restarts; backup copy removal queued or done. | each |
| 51 | Close the app, delete it, reinstall from TestFlight. | Clean onboarding. | first screen |
| 52 | Onboarding: look for "Restore from iCloud". Restore. **[RAJ]** if asked for Apple ID. | All purchases back; totals match step 49's CSV; Google token not restored. | restored Home |
| 53 | Restore again. | No duplicates. | Activity count |
| 54 | Widgets again (they may need to be re-added). | Match the restored data. | widgets |
| 55 | Re-do the Apple Pay setup check (Shortcut still there). **[RAJ]** one more tap if time. | Works without redoing setup. | Activity |
| 56 | Notifications again: bill reminder still scheduled? | Yes, or re-created. | list |
| 57 | App Lock again after restore. | Still on or off as before; no lock-out. | setting |
| 58 | Developer menu (About, hidden): Send test report to Sentry; Recent errors. | Report arrives in Sentry; errors list has no shop names. | list |
| 59 | Force a crash (Developer menu), reopen. | Reopens clean; the crash appears in Sentry (consent on). | Sentry page |
| 60 | Consent off; force a crash again. | Nothing new in Sentry. | Sentry page |
| 61 | Settings › Account: Delete Account (throwaway Apple ID, prod Worker). **[RAJ]** | Apple revoke and PostHog delete both succeed; purchases kept unless chosen. | result |
| 62 | Delete Account offline (airplane), then go online. | Queued; sent after reconnect; once. | before and after |
| 63 | Reboot the phone. Do not unlock. **[RAJ]** Tap Apple Pay at a till or run the shortcut. Then unlock. | Tap appears after unlock; nothing lost. | Activity |
| 64 | Next day: open Home, check "Today", widgets, a reminder. | Right day. | Home |
| 65 | Two-finger screenshot of Home while App Lock on. | Allowed; note it (iOS cannot block screenshots). | none |
| 66 | TestFlight feedback: take a screenshot in the app, send feedback. | Arrives in App Store Connect. | TestFlight sheet |
| 67 | Install the next TestFlight build over this one. | Data, settings, lock and backup intact. | Home |
| 68 | Check Settings › Battery for Sortd after the run. | Small share. | battery list |
| 69 | Look at Xcode Organizer or Sentry for any crash from the run. | None unexpected. | list |
| 70 | Write the times from the notes file into the report. | Complete. | none |

### C2. First-time-user timed pass (no sample data)
Do this on a clean install, with someone (or Raj) who has not used Sortd in 2 weeks. Do not explain anything. Use a stopwatch.
- T0: icon tapped. T1: first screen read. T2: setup done. T3: first purchase logged (by hand). T4: first Apple Pay purchase logged (needs a real tap, so count setup time only, up to the point the user says "I am done").
- Pass marks (proposed): T2 under 3 minutes; T3 under 5 minutes from T0; Apple Pay setup under 5 minutes.
- Write every place the person: stops for more than 3 seconds, reads a sentence twice, taps the wrong thing, asks "what does this mean", scrolls back, or hunts for a button. Each one is a finding with severity "usability".
- Check: can the user explain, in their own words, what "Logs Apple Pay taps" means and what Sortd does not do (no bank login, cash invisible, refunds do not come back; `CLAUDE.md` Known gaps)?
- Check the first-screen "Explore with sample data" choice does not confuse; and that the empty Home says what to do next.

### C3. Acceptance: Raj's sign-off on his phone, in person (the "feel check")
Raj does these himself, with his own phone, before upload. Each is yes or no. (`sortd-feel-first` memory: how it feels in the hand is the top priority.)
1. Open the app cold. It feels instant. No white flash, no jump.
2. Add a purchase with one hand. It feels easy; the keyboard does not cover the Save button.
3. Scroll Activity fast. It feels smooth and never stutters.
4. Tap each tab; transitions feel like the rest of iOS. Haptics feel light, not buzzy.
5. Turn on App Lock; it unlocks fast with Face ID, never loops, never locks right after unlock.
6. A real Apple Pay tap shows up in Sortd within a minute without opening the app.
7. Delete All Data then Restore: everything is back and the numbers match.
8. Widgets look right on the Home and Lock Screens, and tapping them goes to the right place.
9. Dark mode and the biggest text still look good.
10. You would show it to a friend today. If any answer is no, write why in one line.

---

# Section D. Report template

One row per finding, in `docs/BugHunt-<date>.md` style. Every finding goes to `finding-verifier` before it is called a bug.

| Column | What to write |
|---|---|
| id | Area letter + number: `M` money, `D` data/backup, `S` statement, `U` UI/widget/intent, `A` account/sync, `P` privacy/security, `C` crash/stress, `K` compatibility, `F` performance, `O` onboarding/Apple Pay, `L` usability. Example `D7`. Use `S-xx` ids from this plan as `[S-xx]` in the title. |
| area | Section name from A1 to A9 or B |
| title | One plain line: what is wrong, not how |
| where | `file:line` and the build (Debug, Release, TestFlight, build number), OS version, device or simulator name, locale and calendar |
| steps to reproduce | Numbered, exact inputs (copy the string), starting from a state anyone can reach (clean install, sample data, or a named file) |
| expected | What should happen, and the rule it comes from (attacks line, MASVS control, spec, Apple guide) |
| actual | What happened, including any error text and whether the app crashed, hung, lost data or showed wrong money |
| severity | `Blocker` (crash, data loss, wrong money, privacy leak) / `Fix before TestFlight` / `Fix soon` / `Low` / `Note` |
| evidence | Screenshot or video path (`xcrun simctl io ... recordVideo`), log lines, crash report `.ips`, trace file, test name, Sentry link |
| fix | Suggested change in one or two lines, or "unknown" |
| status | `spotted` / `traced` (read in code) / `proved` (reproduced by a run or test) / `verified` (finding-verifier) / `fixed` (commit) / `retested` |

Also keep one line per run at the top: build, date, runtime, device, who ran it, which sections were done and which were skipped and why.

---

# Section E. Sources

URLs I read or searched. "Partial" means the page text came back only in part, so what I used from it is limited and marked.

1. OWASP MASVS v2 (groups and control IDs; control wording not shown by my fetch, so wording in A1.1 is my paraphrase, not verified): https://mas.owasp.org/MASVS/
2. OWASP MASTG iOS test index (test IDs and titles used above): https://mas.owasp.org/MASTG/tests/ , with example pages https://mas.owasp.org/MASTG/tests/ios/MASVS-STORAGE/MASTG-TEST-0052 and https://mas.owasp.org/MASTG/tests/ios/MASVS-STORAGE/MASTG-TEST-0302/
3. MASTG-TEST-0370, input validation in custom URL scheme handlers: https://mas.owasp.org/MASTG/tests/ios/MASVS-PLATFORM/MASTG-TEST-0370/ (0371 source validation is in the index [2])
4. Apple, "Diagnosing memory, thread, and crash issues early" (flags, overheads, TSan not on device, UBSan C-only, Main Thread Checker): https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early.md
5. Apple, MetricKit (daily metrics, diagnostics immediate on iOS 15+, async `MetricManager` on iOS 27): https://developer.apple.com/documentation/metrickit.md . Simulator support: not in the page; not verified.
6. Apple, "Preparing to use the App Attest service" (apps run in production after TestFlight or App Store regardless of the entitlement; sandbox vs production keys): https://developer.apple.com/documentation/devicecheck/preparing-to-use-the-app-attest-service.md . Related thread: https://developer.apple.com/forums/thread/788074
7. Apple, TestFlight overview (90 days, 100 internal and 10,000 external testers, first build reviewed, feedback via screenshot): https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/
8. Apple Forums, SwiftData "Editors must register their identifiers" crash (leaked ModelActor, multiple containers): https://developer.apple.com/forums/thread/797715
9. Apple Forums, SwiftData crash on fetch after migration with `originalName`: https://developer.apple.com/forums/thread/765423
10. Apple Forums, disk full and store-open crashes (search results only, not read in full): https://developer.apple.com/forums/thread/760119 , https://developer.apple.com/forums/thread/769329
11. Big List of Naughty Strings (`blns.txt`, `blns.json`, MIT): https://github.com/minimaxir/big-list-of-naughty-strings
12. SecLists Fuzzing folder (Unicode, special chars, number lists, a copy of the naughty strings): https://github.com/danielmiessler/SecLists/tree/master/Fuzzing
13. csv-spectrum, CSV acid-test files (quotes, escapes; licence and BOM/CRLF coverage not confirmed): https://github.com/max-mapper/csv-spectrum
14. PDF.js test PDFs including fuzzed and malformed files (Apache 2.0): https://github.com/mozilla/pdf.js/tree/master/test/pdfs
15. Monkey tools: https://github.com/testableapple/xcmonkey and https://github.com/zalando/SwiftMonkey (found by search; working on Xcode 27 not verified)
16. Network Link Conditioner (Mac tool affects the whole Mac; device Developer settings): https://useyourloaf.com/blog/network-link-conditioner/
17. CloudKit account status handling (`CKAccountChanged`): https://cocoacasts.com/handling-account-status-changes-with-cloudkit and https://developer.apple.com/forums/thread/771870 (search snippets)
18. Non-Gregorian calendar problem on Thai devices (Android and Java source; the iOS behaviour is not verified, so `[S-01]` needs a run): https://community.appinventor.mit.edu/t/chart-component-simpledateformat-calls-missing-locale-arg-buddhist-year-labels-on-thai-devices/172267
19. Instruments from the command line (third-party notes; commands also checked against local `xcrun xctrace help record` and `xctrace list templates`): https://playbooks.com/skills/charleswiltgen/axiom/axiom-xctrace-ref
20. Local checks on this Mac, Xcode 27.0 (27A266a), macOS 27.0: `xcodebuild -help`, `xcrun xctrace help record`, `xcrun xctrace list templates` and `list instruments`, `xcrun simctl help` and subcommand help (`launch`, `ui`, `keychain`, `privacy`, `io`, `status_bar`, `get_app_container`, `icloud_sync`).
21. Not given to me as URLs (so not cited): the r/iOSProgramming and r/softwaretesting threads and the two 2026 mobile pentest guides and the staged testing guide Raj shared. The lines in A6, A8 and C2 that come from them are restated in my own words.

Repo files read (read-only): `CLAUDE.md`, `docs/testing/attacks.md`, `docs/BugHunt-2026-09-22.md`, `docs/BugHunt-2026-09-26.md` (first part), `docs/TestFlightWhatToTest.md`, `docs/AppStoreChecklist.md` (top), `Spend-Info.plist`, `Spend.entitlements`, `Spend/PrivacyInfo.xcprivacy` (top), `Spend/Services/{Keychain,KeychainBackupKeyStore,AppLock,Router,CrashReporting,ErrorLog,SpendStore,FXService,CloudBackup,CloudKitBackupStore,Analytics,WidgetSummary,Perf}.swift`, `Spend/App/SpendApp.swift`, `worker/README.md`, `worker/wrangler.jsonc`, `worker/src/handler.ts`, `scripts/test.sh`, `scripts/device.sh`, `Spend.xcodeproj/project.pbxproj` (settings lines), `SpendTests/StatementSpeedBenchmark.swift`.
Files not read in full (so findings about them are guesses): `worker/src/attest.ts`, `challenge.ts`, `AccountStore.swift`, `Backup.swift`, `StatementImport.swift`, `LogWalletTapIntent.swift`, `WidgetBridge.swift`, `GmailCleanup.swift`.

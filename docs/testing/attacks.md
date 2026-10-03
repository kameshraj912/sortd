# Attack list

Written 24 Sep 2026. The list `abuse-tester` works from, one section per bug-hunt area
(the section names match `.claude/workflows/bug-hunt.js`). Each line: input → what
should happen. Tags: `[H]` from the 21 findings in `HANDOVER.md`, `[B]` from
`docs/BugHunt-2026-09-22.md` (fixed there; check it has not come back), no tag = new idea.
A line that fails becomes a test tagged `.knownBug`, then goes to `finding-verifier`.
Add lines when a hunt or a user report finds something new.

## money-parsing

- `MYRTLE CAFE 8.00` → AUD 8.00 (home currency), not ringgit. Markers match whole words. [H]
- `CARMENS 12.00` → not RM; `HOURS. 12.00` → not Indian rupees `RS.`. [H]
- `RM 12.00` and `MYR12.00` → ringgit. Word match must not break the real markers. [H]
- `A$-4.50` and `-A$4.50` and `A$4.50-` and `(A$4.50)` → all a refund of 4.50. [H]
- `12.345` → 12.35 or rejected, never 12,345. [H]
- `4111 1111 1111 1111` (a 16-digit card number) → not an amount. [H]
- `Card ending 4821, A$9.00` → 9.00, not 4821. [H]
- `2 x A$4.50` → 4.50 per item or 9.00 total, never 2. [H]
- `¥1200`, `฿350`, `CHF 12.50`, `₱250`, `CN¥88` → JPY, THB, CHF, PHP, CNY kept, not dropped. [H]
- `¥1200` → shown as ¥1,200, no cents. Same for KRW, VND, IDR. [H]
- `payment for $58.30` → currency is USD or home dollars, never "FOR". [B]
- `rent 1,200` → 1,200; `laptop 1,299` → 1,299, not 9. [B]
- `1.234,56` (EU decimal comma) → 1,234.56; `4,5` → 4.50. [B]
- `Rs. 500` → INR 500. `Rs.500` and `Rs500` too. [B]
- `１２.５０` (full-width digits) → 12.50 or rejected, never a crash. [B]
- `١٢٫٥٠` (Arabic-Indic digits and decimal sign) → 12.50 or rejected, never a crash.
- `12 345,67` with a narrow no-break space (U+202F, fr_FR) → 12,345.67.
- `1'234.50` (de_CH apostrophe) → 1,234.50.
- `A$ 0.00` → not logged as a purchase.
- `A$999999999999.99` → rejected as absurd, no overflow, no crash.
- `A$4.50 A$5.00` (two amounts) → the total line wins, or ask; never the first by accident.
- `S$25` in an SGD-home profile → no FX step; in AUD home → one FX step, not two.
- `$25` with no country marker → the home currency, and flagged as a guess.
- Emoji in the amount string `💸A$4.50` → 4.50.
- A 10,000-character string with no digits → nil, returns in under 50 ms.
- `NaN`, `inf`, `1e5` → rejected, not parsed by `Double()`.


## data-backup

- A Gmail receipt that merges into a purchase pending delete → the purchase is kept or cleanly re-added, not lost. [H]
- A backup with the same id twice → restored once; total not doubled. [H]
- Restore the same backup twice → no new rows the second time. [H]
- A backup row with a negative amount → treated as a refund or rejected; no month below zero. [H]
- Backup from an SGD-home phone restored on an AUD-home phone → totals converted once, right. [B]
- "Replace Everything" → monthly budget converted once, not twice. [B]
- Restore then reconnect Gmail → deleted purchases stay deleted. [B]
- A backup with sample data in it → sample data can still be cleared. [B]
- A truncated backup file (cut halfway) → clear error, nothing half-imported.
- A backup from a newer app version with an unknown field → field ignored or clear error, no crash.
- A backup with an unknown category or card raw string → falls back to Other, row kept.
- Two payments of A$4.50 at one shop a minute apart, different cards → two rows. [H]
- Two identical taps two seconds apart from one card → one row (true duplicate).
- A recharge after a refund at the same shop → counted. [H]
- A refund tap more than 10 minutes after the purchase → lowers the total, or does not say "Refund noted". [B]
- Delete a purchase while a sync is inserting its twin → one outcome, no crash.
- Schema change with an old store on disk → migrates, no launch crash. [B]
- Device storage full during save → error shown, no half-written store.
- A purchase on 29 Feb 2028 → shows in February, monthly totals right.
- A tap at 02:30 on the DST change day (Sydney, first Sunday of October) → one row, right day.
- A tap at 23:59 in Singapore, phone later set to Sydney → stays on the day it happened.
- Export to CSV with a merchant containing a comma, quote or newline → the CSV still opens right.

## ui-intents-widget

- Widget after a tap, add, edit or delete → refreshed. "Today" after midnight → today. [B]
- Wallet tap text `A$1234.50` with no commas → 1,234.50, not 123. [B]
- Shortcut text with newlines between fields → parsed the same as one line.
- Shortcut text with the merchant missing → logged as "Unknown" with the amount, not dropped.
- Shortcut text with the amount missing → nothing logged, and the Last Tap line says why.
- Shortcut text that is empty or only spaces → nothing logged, no crash.
- Shortcut text in another language (e.g. Japanese date and ¥ amount) → amount and currency right.
- `LogPurchaseIntent` with nil amount, nil merchant or nil card → clear Siri error, no crash.
- `LogPurchaseIntent` amount 0 or negative → refused, or logged as a refund when negative.
- Two taps delivered at the same moment → two rows, no lost write.
- Siri "Upcoming Bills" as a free user → Pro prompt, not the data. [B]
- Bills widget tap → opens Subscriptions & Bills. [B]
- Merchant with RTL text (`مطعم`), mixed with a Latin amount → row and VoiceOver read in the right order.
- Merchant with emoji and ZWJ (`👩‍🍳 Kitchen`) → no broken glyphs, no clipping.
- Merchant 200 characters long → truncated with an ellipsis; amount never cut.
- Amount `A$123,456.78` on iPhone SE at AX5 Dynamic Type → fully visible or wraps; never "A$12…".
- VoiceOver on any amount → spoken with `Money.spoken()` ("25 Singapore dollars").
- Dark mode and Increase Contrast → text still passes 4.5:1.
- Reduce Motion on → no zoom transition, cross-fade instead.
- Free and lapsed users → no Pro reminders. [B]

## statement-import

- Full-width (`１２`) or Arabic (`١٢`) digits in a date → skipped or parsed, never a crash. [B]
- `12.50 1,034.20` (amount then running balance) → 12.50. [B]
- `CAFE 12 MARKET` → the date is not 12 March. [B]
- A year-less `28 Dec` imported in January → last December, not this one. [B]
- Two identical rows in one statement → two purchases. [B] [H]
- Import the same statement twice → no new rows the second time. [H]
- A row with no date → kept with a flag, or listed as skipped. Never silently dropped. [H]
- `31/02/2026`, `01/01/1900`, `01/01/2099` → rejected as absurd. [H]
- `03/04/2026` in an AU statement → 3 April, not 4 March. US-format banks are detected, not guessed per row.
- A CSV with a BOM, CRLF endings, or `;` as the separator → parsed.
- A CSV where the merchant cell has a quoted comma (`"SMITH, JOHN & CO"`) → one column.
- Debits and credits in separate columns → credits are refunds, not purchases.
- A PDF with the table split across pages → no row lost or doubled at the page break.
- A 10,000-row statement → imports with a spinner, UI stays responsive, finishes.
- A file that is not a statement (a photo renamed .csv) → clear error.
- Amounts in brackets `(45.00)` → a credit.
- A merchant with Unicode (`Café Déjà Vu`, `東京ラーメン`) → kept as is, categorised, de-duplicated.
- Statement currency differs from home currency → converted once at the row's date.


## security-masvs

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

## crash-and-stress

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

## deep-links-and-intents

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

## account-sync-safety

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

## onboarding-and-applepay

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

## input-and-monkey

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

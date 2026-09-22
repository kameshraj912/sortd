# Performance pass — 22 Sep 2026

Branch `speed-loading` (from `beta-rc1`). The complaint: "Connecting Gmail takes forever and I don't
know whether the app is glitching or connecting." Goal: make it faster, and when it must take
time, say what's happening.

## How it was measured

- **Signposts + log.** New `Perf` helper (`Spend/Services/Perf.swift`). `OSSignposter` intervals
  (Instruments › os_signpost, subsystem `com.kameshraj.spend`, category `perf`) plus a debug-level
  log line with the time. Cheap enough to leave on in Release. To watch:
  `log stream --level debug --predicate 'subsystem == "com.kameshraj.spend" && category == "perf"'`
- Marks added: `launch.init`, `launch.container`, `launch.cardScan`, `launch.firstActive`,
  `launch.activeTasks`, `launch.proRefresh`, `launch.recategorise`, `auth.googleSheet`,
  `auth.tokenExchange`, `gmail.connect`, `gmail.sync`, `gmail.token`, `gmail.list`,
  `gmail.skipKnown`, `gmail.fetchAndImport` (with time spent reading and saving),
  `fx.backfill`, `fx.fetch`, `fx.afterGmail`, `widget.refresh`, `statement.read`, `statement.save`.
- **Simulated Gmail.** Real Gmail can't be hit from here. `SpendTests/GmailPipelineTests.swift` has a
  pretend Gmail behind `URLProtocol` (paging, 404s, 429s, a fixed delay per request, and it counts
  requests in flight). `SpendTests/GmailSpeedBenchmark.swift` runs the **old** pipeline (rebuilt
  in the test) and the **new** one against it. Off by default; run with
  `TEST_RUNNER_SPEND_BENCH=1 xcodebuild … test -only-testing:SpendTests/GmailSpeedBenchmark`.
- Setup: 300 receipt emails (bank alerts, exact rules), 150 ms per Gmail request, on-disk SwiftData
  store, iPhone 18 Pro simulator on a Mac. Real phones on mobile data will be slower per request;
  the ratios should hold.

## Before → after (simulated)

| Phase (300 emails, 150 ms/request) | Before | After |
|---|---|---|
| List message ids | 510 ms (3 pages of 100) | 164 ms (1 page of 500) |
| First purchase on screen | 2,023 ms — and it was the **oldest** one | 508 ms — the **newest** ones |
| Whole first sync | 14,420 ms | 8,594 ms (−40%) |
| Reading emails on the main thread | 415 ms | ~0 (rules run next to the download) |
| Saving 300 purchases | 716 ms (one save each) | 392 ms (a save every 10) |
| Statement import, 300 rows | 407 ms | 124 ms |
| What the person saw | "Connecting…" spinner the whole time | each step in words, with a count and a bar |

Launch (Debug, simulator, sample data, 3 runs): `launch.init` 137–192 ms, of which opening the
SwiftData store (`launch.container`) is 109–157 ms and the card scan 5–11 ms. Work after the
first frame (`launch.activeTasks`) 123 ms, most of it the StoreKit check (70 ms). `launch.firstActive`
in the simulator was noisy (the scene often didn't activate while the simulator window was in the
background) — measure it on a phone.

## Bottlenecks found

1. **Nothing to see.** The Connect sheet showed "Connecting…" from Google's page until the whole
   sync ended. No count, no step, no way to leave. This was the main complaint.
2. **Downloads in lock-step.** Emails came 20 at a time in groups of 4; each group waited for its
   slowest email, and nothing downloaded while a batch was being read and saved.
3. **Oldest first.** The first purchases to appear were four months old.
4. **Small pages.** The id list used 100 per page — up to 10 round trips before any email downloaded.
5. **Main-thread reading.** All parsing (regexes) ran on the main actor.
6. **One disk save per purchase**, each also waking the widget refresh and every `@Query` on screen.
   Merchant rules were re-read from the store for every purchase.
7. **Double sync on connect.** Closing Google's sheet makes the app active, which started the app's
   own sync of the same inbox alongside the connect's. Connect also re-synced every other account.
8. **One error ends it all.** An email deleted between list and download (404) failed the whole sync.
   429s retried at fixed 2/5/10 s, all parallel downloads retrying together; 5xx never retried.
9. **FX.** Every pass re-downloaded rates even when the saved ones covered the day; launch and a
   Gmail sync ran two passes at once; up to 7 queries per purchase; 60 s default timeout; failures
   were silent.
10. **Widget.** Reloaded after every save during a sync (WidgetKit budgets reloads).

## What changed, per file

- `Services/GmailSync.swift` — New `GmailAPI` (injectable session, retries, concurrency). Sliding
  window of 6 downloads (a new one starts when one finishes). Gmail's quota is 250 units/user/s and
  a message get is 5, so 6 in flight stays under it with room for a second account. Newest first;
  saves every 10 emails or 1 s. Refunds and DoorDash "order adjusted" emails wait to the end and go
  in oldest first, so they still find their purchase. Rules and the plain fallback run off the
  main thread; only the on-device model and SwiftData stay on the main actor. 500 ids per page,
  `fields=` to trim responses. 404 = skip. 429/403-rate-limit/500/503 retry with doubling backoff,
  jitter and `Retry-After`. What was read before an error is saved. `connect` syncs only the new
  account, and the app's own sync steps aside while a connect runs. `startConnect` / `startSync`
  run as tasks that outlive the screen.
- `Services/SyncStatus.swift` (new) — Shared progress model, with each step in plain words; job
  ownership so a background sync never overwrites a sync the person started; quiet mode for
  app-open syncs; VoiceOver announcements per step and every 25%; failures sorted into offline /
  access denied / access ended / slow down / Google error, each one short sentence.
- `Services/GoogleAuth.swift` — `signIn(onAuthorized:)` so the UI can switch to "Connecting your
  Gmail…" the moment Google's page closes; 20 s timeout on token calls; signposts.
- `Services/EmailSync.swift`, `Services/SpendStore.swift` — `TransactionLogger.log(…, learned:, save:)`;
  bulk imports read rules once and save once per batch (fetches still see unsaved rows).
- `Services/StatementImport.swift` — Same batching for statements (save every 50 rows + at the end).
- `Services/FXService.swift` — Uses saved rates when they cover the day (re-downloads a pair at most
  every 6 h). Concurrent callers share one pass. Rates are read once per pass. 15 s timeout.
  Returns an `Outcome` with a plain sentence.
- `Services/WidgetBridge.swift` — `hold()` / `release()`: one widget refresh per bulk import.
- `App/SpendApp.swift` — Launch signposts; the card scan fetches only `cardRaw`; retrying pending
  revokes no longer holds up the rest of the app-open work.
- `Services/Perf.swift` (new) — signposts and timing.
- `Views/Components/SyncStatusViews.swift` (new) — `SyncProgressCard`, `GmailStatusBanner`.
- `Views/GmailViews.swift` — Connect sheet shows the steps; "Close" once past Google (work
  continues); Settings "Sync Now" shows the same card.
- `Views/HomeView.swift` — one line: the banner as a bottom inset.
- `Views/OnboardingView.swift` — the email step shows the card if a connect is still running.
- `Views/ImportView.swift` — "Reading your statement…", "Adding N purchases…", VoiceOver line when done.
- `Views/Settings/CurrencySettingsView.swift` — "Updating rates…" and a one-line result.
- Debug flag `SPEND_SYNC_DEMO=signin|connecting|searching|adding|done|offline|expired` (inside
  `#if DEBUG`, added to CLAUDE.md and `scripts/preflight.sh`).

## Loading states

Opening Google sign-in… → Connecting your Gmail… → Looking for receipts… (found N) → Adding
purchases… X of N emails checked (a bar, plus "N added so far") → Done. N purchases added.
Errors: "You're offline. Connect to the internet and try again." / "Google access has ended.
Connect Gmail again." / "Sortd needs the Gmail box ticked to read receipts." / "Gmail asked Sortd
to slow down. What's read is saved. Try again in a minute." / "Gmail had a problem. Try again in a
moment." — each with Try Again or Connect Again. Home shows a small card while it runs (with a
bar), "Done" for 6 s, and errors until dismissed. App-open syncs stay quiet unless they add
something, or access has ended.

## What's left

- **Only a phone with real Gmail can confirm:** real per-request time on 4G/5G; whether 6 at once
  ever hits 429 on a large inbox (if it does, try 4 — it's one constant); time spent in Google's
  sheet and the token exchange; `fields=` accepted on `messages.get` (it's a standard parameter —
  confirm messages still parse); the on-device model's time per unknown-sender email.
- **On-device AI is still one email at a time.** For inboxes full of unknown senders it's the limit
  (~0.5–2 s each). Running 2 sessions at once may help; untested.
- **Gmail batch HTTP** (up to 50 gets per request) would cut round trips further. The quota is
  still per message, so the gain is latency, not throughput.
- **Opening the store** (~110–160 ms before the first frame) is SwiftData's own cost.
- `refreshUncategorised` walks every purchase on each app open (6 ms with sample data; grows with
  history).

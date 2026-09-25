# Overhaul 2b: Sentry crash reports in the live app (25 Sep 2026)

Part of `2026-09-25-free-app-overhaul-overview.md`. Ships in the same release as 2.
**Raj decided on 25 Sep:** keep Sentry, and run it in the live app.

## Problem

`CrashReporting.isOn` is true only under `SORTD_BETA` with a DSN (`CrashReporting.swift:19-25`), and the DSN is empty. Sub-spec 1 removes `SORTD_BETA`, so without this change crash reporting would never run. Today `scripts/preflight.sh:44-51` fails any App Store build that links Sentry.

## Options

| | A. Sentry on in Release, scrubbed (decided) | B. Xcode Organizer only |
|---|---|---|
| Crash-free rate and stack traces | yes, from every opted-in user | only from users who share data with developers |
| Label | adds Crash, Performance and Other Diagnostic Data | unchanged |

## Design

**Turning it on:**
- `isOn` becomes `!DEBUG && !dsn.isEmpty && Analytics.consented`: one switch shared with sub-spec 2.
- Raj creates the Sentry project and pastes the DSN.

**Keep the scrubbing already in `CrashReporting.start()`:**
- `sendDefaultPii = false` (the default). Sentry says its SDK "doesn't send the user's IP address", and its backend infers the IP only when this setting is true.
- No screenshots, view hierarchy, breadcrumbs, network tracking or replay. Replay sample rates are 0 by default.

**Add:**
- Scrub `event.exceptions[].value` and `event.message`. Keep only the type and the stack. An error string could carry a merchant name or Gmail text.
- Keep `enableAutoSessionTracking` on (the default is true). It gives the crash-free rate. Performance tracing stays at 0.
- `SentrySDK.setUser(id: Analytics.identityHash)` and nothing else. This joins crashes to the PostHog person, and makes Crash Data **linked**, as Raj chose.
  - Sentry's own manifest declares Crash, Performance and Other Diagnostic Data as *not* linked, purpose App Functionality. Our app manifest and the label must say linked.
  - Whether our manifest overrides the SDK's in Xcode's privacy report is **not verified**.
  - Option: skip `setUser`, and Crash Data stays not linked, like Copilot, Spendee and Buddy (see the table in sub-spec 2).

**Preflight:** `--appstore` fails if the DSN is empty. It no longer fails because Sentry is linked.

**Leaked DSN:** someone could send junk events. Sentry's rate limits and spike protection may limit this (**not verified**). Rotate the client key in Sentry and ship an update.

## Files

- `Spend/Services/CrashReporting.swift`
- `Spend/PrivacyInfo.xcprivacy`
- `scripts/preflight.sh:42-51`
- Docs (router): the Sentry section of `docs/AppStoreChecklist.md`, and `docs/AppReviewNotes.md`

## Test plan

- `CrashReporting.isOn`:
  - DSN set, consent on, Release → true
  - consent off → false
  - DSN empty → false
  - DEBUG → false
- `scrub(event)` with the exception value "Bad amount at Coles 12.50":
  - the value is empty; the type and stack are kept
  - `user.id` is the hash only
  - there is no `ip_address`
- `beforeBreadcrumb` returns nil for every breadcrumb.
- Device (TestFlight): a forced crash shows in Sentry with the stack and device model. No IP, no merchant text, and the user ID is the hash.

## Gate

- Raj provides the DSN.
- The label and in-app privacy copy change in the same release.
- The forced-crash check passes.

## Sources (read 25 Sep 2026)

- [Sentry Apple privacy manifest](https://docs.sentry.io/platforms/apple/data-management/apple-privacy-manifest/)
- [Sentry options](https://docs.sentry.io/platforms/apple/configuration/options/)
- [Sentry data collected](https://docs.sentry.io/platforms/apple/data-management/data-collected/)

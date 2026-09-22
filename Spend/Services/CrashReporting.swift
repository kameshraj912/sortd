import Foundation
import Sentry

/// Crash reports for TestFlight testers, nothing else.
///
/// Only ever active in a `SORTD_BETA` build (TestFlight — the App Store build never
/// defines `SORTD_BETA`, so `isOn` is always false there) and only once `dsn` below is
/// filled in. Leave `dsn` empty and nothing starts: no Sentry call, no network
/// connection, no data leaves the phone.
///
/// To turn it on for the App Store later: change `isOn` to also cover the App Store
/// build, set the App Privacy label to "Diagnostics › Crash Data, not linked to you",
/// and update the "no analytics" wording on sortd.page, the listing and the in-app
/// Privacy page. `scripts/preflight.sh --appstore` fails until then.
///
/// Privacy, on purpose — every option below is set explicitly, not left to the SDK's
/// default, so a future SDK update can't quietly turn one on:
/// - **No PII.** `sendDefaultPii = false`. No name, no email, no purchase history —
///   Sortd never tells Sentry who you are.
/// - **No screenshots, no view hierarchy.** `attachScreenshot` / `attachViewHierarchy`
///   both false — a view hierarchy can leak on-screen amounts and merchant names even
///   without a literal screenshot.
/// - **No breadcrumbs.** Auto breadcrumb tracking, network breadcrumbs and network
///   tracking are all off, and `beforeBreadcrumb` drops anything that slips through
///   anyway — no trail of taps, screens or requests riding along with a crash.
/// - **No session/usage tracking.** `enableAutoSessionTracking = false` — this is
///   crash reporting, not a ping every time the app opens.
/// - **No tracing, no session replay.** `tracesSampleRate` and both session-replay
///   sample rates are 0.
/// - **Belt and suspenders.** `beforeSend` strips `user`, `request`, `breadcrumbs`,
///   `extra` and `tags` from every event right before it's sent, in case any option
///   above is ever loosened by mistake later.
/// - **IP address — needs one more step, done once in the Sentry dashboard, not in
///   code.** `sendDefaultPii = false` stops the SDK from *attaching* an IP to events,
///   but on Apple platforms Sentry's server still infers the sender's IP from the
///   network connection regardless of that setting (checked against Sentry's current
///   docs, "Users — IP address", 22 Sep 2026). Turn that off too, once: Sentry project
///   → Settings → Security & Privacy → "Prevent Storing of IP Addresses". See
///   `docs/AppStoreChecklist.md`.
///
/// What actually reaches Sentry: the crash/exception, a stack trace, the device
/// model, iOS version, and Sortd's version/build number. Nothing typed, nothing
/// bought, nothing from Gmail or the camera.
enum CrashReporting {
    /// From sentry.io › Project Settings › Client Keys (DSN). Empty = off.
    static let dsn = ""

    static var isOn: Bool {
        #if SORTD_BETA
        return !dsn.isEmpty
        #else
        return false
        #endif
    }

    static func start() {
        guard isOn else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            options.sendDefaultPii = false
            options.attachScreenshot = false
            options.attachViewHierarchy = false
            options.enableAutoPerformanceTracing = false
            options.tracesSampleRate = 0
            options.enableAutoBreadcrumbTracking = false
            options.enableNetworkBreadcrumbs = false
            options.enableNetworkTracking = false
            options.enableCaptureFailedRequests = false
            options.enableAutoSessionTracking = false
            options.sessionReplay.sessionSampleRate = 0
            options.sessionReplay.onErrorSampleRate = 0
            options.beforeBreadcrumb = { _ in nil }
            options.beforeSend = { event in
                event.user = nil
                event.request = nil
                event.breadcrumbs = nil
                event.extra = nil
                event.tags = nil
                return event
            }
        }
    }
}

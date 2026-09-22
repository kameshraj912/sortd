import Foundation
#if canImport(Sentry)
import Sentry
#endif

/// Crash reports for TestFlight testers, nothing else.
///
/// This only ever does anything in a `SORTD_BETA` build (TestFlight — see
/// `docs/AppStoreChecklist.md`; the App Store build never defines
/// `SORTD_BETA`, so this whole thing compiles away to nothing for it), and
/// only once `dsn` below is filled in. Leave `dsn` empty and nothing starts:
/// no Sentry SDK call is made, no network connection, no data leaves the
/// phone. That's the current state — this file is wired up and waiting for
/// a DSN.
///
/// Setup for the owner: create a Sentry project and paste its DSN into
/// `dsn`, then link the Sentry SDK to the Xcode project (File > Add Package
/// Dependencies > `https://github.com/getsentry/sentry-cocoa`, added to the
/// Spend target) if it isn't linked yet — this file works either way, it
/// just stays a no-op until the package is present (`canImport(Sentry)`)
/// and the DSN is set. `CrashReporting.start()` also needs one line calling
/// it early in `SpendApp.init()`, which isn't in this file's scope.
///
/// Privacy, on purpose — every option below is set explicitly, not left to
/// the SDK's default, so a future SDK update can't quietly turn one on:
/// - **No PII.** `sendDefaultPii = false`. No name, no email, no purchase
///   history — Sortd never tells Sentry who you are.
/// - **No screenshots.** `attachScreenshot = false`.
/// - **No view hierarchy.** `attachViewHierarchy = false` — this can leak
///   on-screen text (amounts, merchant names) even without a screenshot.
/// - **No breadcrumbs.** `enableAutoBreadcrumbTracking = false` and
///   `maxBreadcrumbs = 0`, so a crash report doesn't carry a trail of taps,
///   screens and network calls that led up to it — just the crash itself.
/// - **No session/usage tracking.** `enableAutoSessionTracking = false`.
///   This is crash reporting, not analytics on how often you open the app.
/// - **No tracing.** `tracesSampleRate = 0` — tracing can record file paths
///   and request URLs, which isn't needed just to see a crash.
/// - **IP address — needs one more step.** `sendDefaultPii = false` stops
///   the SDK from attaching an IP to events, but on Apple platforms
///   Sentry's server still infers the sender's IP from the network
///   connection unless that's turned off on the server side too. That's a
///   one-time setting in the Sentry dashboard, not something this code can
///   reach — see the exact steps wherever this task's report is shown, or
///   Sentry project Settings → Security & Privacy → "Prevent Storing of IP
///   Addresses".
///
/// What this actually sends: the crash or exception, its stack trace, the
/// device model, iOS version, and Sortd's version/build number. Nothing a
/// person typed, nothing they bought, nothing from Gmail or the camera.
enum CrashReporting {
    /// Paste the DSN from the Sentry project here. Empty means off.
    private static let dsn = ""

    static func start() {
        #if SORTD_BETA
        guard !dsn.isEmpty else { return }
        #if canImport(Sentry)
        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = false

            // No PII of any kind (see the doc comment above for the IP caveat).
            options.sendDefaultPii = false

            // No screenshots, no view hierarchy.
            options.attachScreenshot = false
            options.attachViewHierarchy = false

            // No breadcrumbs: just the crash, not a trail leading to it.
            options.enableAutoBreadcrumbTracking = false
            options.maxBreadcrumbs = 0

            // No session/release-health tracking — crash reports only.
            options.enableAutoSessionTracking = false

            // No performance tracing (it can capture URLs and file paths).
            options.tracesSampleRate = 0
        }
        #endif
        #endif
    }
}

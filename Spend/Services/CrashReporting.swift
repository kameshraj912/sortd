import Foundation
import Sentry

/// Crash reports for TestFlight builds only (Sentry).
///
/// Off in Debug and in the App Store build, so the App Store privacy label stays
/// "Data Not Collected". Reports carry the stack trace, device model and OS, and
/// nothing typed or shown in the app: no purchases, merchants, amounts, emails,
/// screenshots, breadcrumbs or IP address.
///
/// To turn it on for the App Store later: change `isOn` to also cover the App Store
/// build, set the App Privacy label to "Diagnostics › Crash Data, not linked to you",
/// and update the "no analytics" wording on sortd.page, the listing and the in-app
/// Privacy page. `scripts/preflight.sh --appstore` fails until then.
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

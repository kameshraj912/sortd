import Foundation
import Sentry

/// Crash reports (Sentry).
///
/// Off in Debug, and off everywhere while `dsn` is empty (it is). Reports carry
/// the stack trace, device model and OS, and nothing typed or shown in the app:
/// no purchases, merchants, amounts, emails, screenshots, breadcrumbs or IP
/// address.
///
/// When and how this runs in the live app, the consent switch, the App Privacy
/// label and the wording on sortd.page are decided in overhaul sub-spec 2b.
/// Until then `scripts/preflight.sh --appstore` fails while Sentry is linked.
enum CrashReporting {
    /// From sentry.io › Project Settings › Client Keys (DSN). Empty = off.
    static let dsn = ""

    static var isOn: Bool {
        #if DEBUG
        return false
        #else
        return !dsn.isEmpty
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

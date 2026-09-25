import Foundation
import Sentry

/// Crash reports (Sentry), overhaul sub-spec 2b.
///
/// Runs in the live app when three things hold: a Release build, a DSN, and
/// the analytics consent switch on (Settings › Privacy, one switch for
/// PostHog and Sentry). Reports carry the exception type, the stack trace,
/// device model and OS, and nothing typed or shown in the app: no purchases,
/// merchants, amounts, emails, screenshots, breadcrumbs or IP address.
/// `scrub` is the last word on every event; `enabled` is the switch. Both are
/// pure so tests pin them without starting the SDK.
///
/// The user is the salted PostHog hash (`Analytics.identityHash`) and
/// nothing else, so Crash Data is "linked to you" on the App Privacy label.
enum CrashReporting {
    /// From sentry.io › Project Settings › Client Keys (DSN). Never in source:
    /// `SENTRY_DSN` in Secrets.xcconfig (gitignored) → Config.xcconfig →
    /// Spend-Info.plist → here. Empty = off. The example file's placeholder
    /// ("replace_me") counts as empty, so a copied example never starts Sentry.
    static let dsn: String = {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.contains("replace_me") ? "" : raw
    }()

    static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Off in Debug, off without a DSN, off without consent.
    nonisolated static func enabled(isDebug: Bool, dsn: String, consent: Bool) -> Bool {
        !isDebug && !dsn.isEmpty && consent
    }

    static var isOn: Bool {
        enabled(isDebug: isDebug, dsn: dsn, consent: Analytics.shared.isEnabled)
    }

    /// Starts Sentry at launch when `isOn`. Safe to call again after
    /// `SentrySDK.close()` (the consent switch coming back on).
    static func start() {
        start(analytics: Analytics.shared)
    }

    /// The consent switch moved. Off closes the SDK so nothing more leaves
    /// the phone; on starts it again. Called from `Analytics.isEnabled`.
    ///
    /// `close()` waits up to `shutdownTimeInterval` for the transport, so it
    /// runs off the main thread and the switch never freezes. Events already
    /// captured under consent (and queued) may still flush during that close;
    /// nothing captured after it leaves.
    static func consentChanged(to on: Bool, analytics: Analytics) {
        if on {
            start(analytics: analytics)
        } else if SentrySDK.isEnabled {
            log.notice("crash reports off: consent withdrawn")
            Task.detached(priority: .utility) { SentrySDK.close() }
        }
    }

    private static func start(analytics: Analytics) {
        guard !isDebug else { log.notice("crash reports off: debug build"); return }
        guard !dsn.isEmpty else { log.notice("crash reports off: no DSN (SENTRY_DSN is empty)"); return }
        guard analytics.isEnabled else { log.notice("crash reports off: consent is off"); return }
        guard !SentrySDK.isEnabled else { return }
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
            // Sessions (start, end, crashed) give the crash-free rate; they
            // carry no user text.
            options.enableAutoSessionTracking = true
            // How long close() waits for the transport (default 2 s).
            options.shutdownTimeInterval = 0.5
            options.beforeBreadcrumb = { @Sendable crumb in CrashReporting.scrubBreadcrumb(crumb) }
            options.beforeSend = { @Sendable event in
                CrashReporting.scrub(event, userId: analytics.identityHash)
            }
        }
        log.info("crash reports on: Sentry, scrubbed")
    }

    /// Context keys Sentry needs to group and show a crash: the device
    /// model, the OS and the app version. Nothing typed in the app lands
    /// there. Everything else in `context` goes; in particular the crash
    /// converter puts an uncaught NSException's userInfo under "user info".
    nonisolated static let keptContext: Set<String> = ["device", "os", "app"]

    /// What may leave the phone: the exception type, its frames and its
    /// mechanism type, the device, OS and app context, and the user id (the
    /// hash). Exception values, the message and the mechanism data (the crash
    /// converter's "crash_info_messages": earlier Swift runtime messages)
    /// go, since an error string can carry a merchant name or Gmail text.
    /// Request, breadcrumbs, extra and tags go whole.
    nonisolated static func scrub(_ event: Event, userId: String?) -> Event {
        for exception in event.exceptions ?? [] {
            exception.value = nil
            exception.mechanism?.data = nil
        }
        event.message = nil
        if let context = event.context {
            event.context = context.filter { keptContext.contains($0.key) }
        }
        if let userId {
            event.user = User(userId: userId)
        } else {
            event.user = nil
        }
        event.request = nil
        event.breadcrumbs = nil
        event.extra = nil
        event.tags = nil
        return event
    }

    /// No breadcrumb, ever: a screen name or a URL is a trail through the
    /// user's purchases.
    nonisolated static func scrubBreadcrumb(_ crumb: Breadcrumb) -> Breadcrumb? {
        nil
    }
}

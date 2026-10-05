import UserNotifications

/// Sends a tap on a Sortd notification to the right screen, using the
/// `sortd://` link the notification carries (the same links widgets use).
///
/// Uses the completion-handler forms, not the `async` ones: with `async`, the
/// system's completion handler runs on a background thread and UIKit aborts
/// with NSInternalInconsistencyException (Sentry SORTD-2, build 1.0 (4)).
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let raw = response.notification.request.content.userInfo["url"] as? String
        Self.deliver(raw, completion: completionHandler)
    }

    /// Still show it when Sortd is open, quietly.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let finish = UncheckedBox(completionHandler)
        DispatchQueue.main.async { finish.value([.banner, .list]) }
    }

    /// Opens the link and calls `completion`, both on the main thread, from whatever
    /// thread the system calls in on.
    nonisolated static func deliver(_ raw: String?, completion: @escaping () -> Void,
                                    open: @escaping @MainActor (URL) -> Void = { Router.shared.open($0) }) {
        let finish = UncheckedBox(completion)
        let open = UncheckedBox(open)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let raw, let url = URL(string: raw) { open.value(url) }
            }
            finish.value()
        }
    }
}

/// Carries a system completion handler across to the main queue. The system's
/// handlers are not marked `Sendable`, but calling them once on main is what it expects.
private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

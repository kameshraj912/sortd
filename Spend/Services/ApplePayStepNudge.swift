import Foundation
import UserNotifications

/// A reminder to finish Apple Pay logging (6 Oct 2026). Both iOS 26 testers
/// left the Apple Pay step undone and nothing ever asked them back; on
/// iOS 26 build 8 lets people in after steps 1 and 2 on purpose, so a
/// reminder is the only thing that brings step 3 back to mind once the app
/// is closed. Two local notifications, a day and three days after the app
/// is last left with logging not set up, each opening the setup page
/// (`sortd://applepay`). Never asks for permission: nothing is posted unless
/// notifications are already allowed. Removed the moment logging works.
enum ApplePayStepNudge {
    static let ids = ["applepay-nudge-1", "applepay-nudge-3"]
    static let delays: [TimeInterval] = [24 * 3600, 3 * 24 * 3600]
    static let url = "sortd://applepay"
    /// Which stage the pending reminders were written for, so leaving the
    /// app again does not push them further out.
    static let stageKey = "applePayNudgeStage"

    /// What is left to do, in the reminder's words.
    enum Stage: String, Equatable {
        /// Nothing has reached Sortd: the whole step is left.
        case notSetUp = "not_set_up"
        /// The shortcut ran, step 3 (the automation) is left.
        case stepThreeLeft = "step_3_left"

        init?(status: ApplePayStatus, saysBuilt: Bool) {
            switch status {
            case .notConnected: self = .notSetUp
            case .shortcutReached: if saysBuilt { return nil } else { self = .stepThreeLeft }
            case .tapLogged, .tapNeedsCheck: return nil
            }
        }

        var title: String {
            switch self {
            case .notSetUp: "Apple Pay isn't logging yet"
            case .stepThreeLeft: "One step left"
            }
        }

        var body: String {
            switch self {
            case .notSetUp: "Set it up once and every tap writes itself down. About a minute. Tap to start."
            case .stepThreeLeft: "Finish step 3 and your taps log themselves. Tap to finish."
            }
        }
    }

    /// What to do when the app is left: schedule for `stage`, or clear when
    /// there is none. Pure, so tests can walk every case.
    enum Plan: Equatable {
        case schedule(Stage)
        case clear
        case leave
    }

    static func plan(stage: Stage?, pendingStage: Stage?, setupDone: Bool, authorized: Bool) -> Plan {
        guard setupDone, authorized else { return .clear }
        guard let stage else { return .clear }
        return stage == pendingStage ? .leave : .schedule(stage)
    }

    /// Called when the app goes to the background.
    @MainActor
    static func update(status: ApplePayStatus, saysBuilt: Bool, setupDone: Bool,
                       defaults: UserDefaults = .standard, now: Date = .now) async {
        let stage = Stage(status: status, saysBuilt: saysBuilt)
        let pending = defaults.string(forKey: stageKey).flatMap(Stage.init(rawValue:))
        let authorized = await LoggedNotice.notificationsAllowed()
        let center = UNUserNotificationCenter.current()
        switch plan(stage: stage, pendingStage: pending, setupDone: setupDone, authorized: authorized) {
        case .leave:
            return
        case .clear:
            guard pending != nil else { return }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            defaults.removeObject(forKey: stageKey)
        case .schedule(let stage):
            center.removePendingNotificationRequests(withIdentifiers: ids)
            for (id, delay) in zip(ids, delays) {
                let note = UNMutableNotificationContent()
                note.title = stage.title
                note.body = stage.body
                note.userInfo = ["url": url]
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: id, content: note, trigger: trigger))
            }
            defaults.set(stage.rawValue, forKey: stageKey)
        }
    }
}

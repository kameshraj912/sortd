import Foundation
import UserNotifications

/// What someone told Sortd about themselves during setup. Kept on this
/// iPhone only. It decides which setup steps show and when the check-in
/// notification comes.
enum SetupProfile {
    static let goalsKey = "setup.goals"
    static let paymentKey = "setup.payment"
    static let checkInKey = "setup.checkIn"
    static let billsKey = "setup.billReminders"
    static let rerunKey = "setup.rerun"

    /// Someone asked for bill reminders during setup and the request is
    /// still pending. Turn them on, once.
    @MainActor
    static func applyPendingBillReminders(defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: billsKey) else { return }
        defaults.set(true, forKey: Reminders.enabledKey)
        defaults.set(false, forKey: billsKey)
    }

    enum Goal: String, CaseIterable, Identifiable, Sendable {
        case seeWhere, spendLess, countries, bills, receipts
        var id: String { rawValue }
        var title: String {
            switch self {
            case .seeWhere: "See where my money goes"
            case .spendLess: "Spend less each month"
            case .countries: "Spend across countries"
            case .bills: "Never miss a bill"
            case .receipts: "Keep receipts together"
            }
        }
        var symbol: String {
            switch self {
            case .seeWhere: "chart.pie"
            case .spendLess: "gauge.with.dots.needle.33percent"
            case .countries: "airplane"
            case .bills: "arrow.triangle.2.circlepath"
            case .receipts: "doc.text"
            }
        }
    }

    enum Payment: String, CaseIterable, Identifiable, Sendable {
        case applePay, card, online, cash, mix
        var id: String { rawValue }
        var title: String {
            switch self {
            case .applePay: "Mostly Apple Pay"
            case .card: "Mostly a bank card"
            case .online: "Lots of online shopping"
            case .cash: "Often cash"
            case .mix: "A mix of all of these"
            }
        }
        var symbol: String {
            switch self {
            case .applePay: "iphone"
            case .card: "creditcard"
            case .online: "shippingbox"
            case .cash: "banknote"
            case .mix: "shuffle"
            }
        }
    }

    enum CheckIn: String, CaseIterable, Identifiable, Sendable {
        case morning, evening, sunday, needed
        var id: String { rawValue }
        var title: String {
            switch self {
            case .morning: "Each morning"
            case .evening: "Each evening"
            case .sunday: "Sunday recap"
            case .needed: "Only when it matters"
            }
        }
        var detail: String {
            switch self {
            case .morning: "8 am, a look at yesterday"
            case .evening: "8 pm, a look at today"
            case .sunday: "Sunday 6 pm, your week"
            case .needed: "No regular check-ins"
            }
        }
        var symbol: String {
            switch self {
            case .morning: "sun.max"
            case .evening: "moon"
            case .sunday: "calendar"
            case .needed: "bell.slash"
            }
        }
        /// How the setup summary says it.
        var summary: String {
            switch self {
            case .morning: "A check-in each morning at 8"
            case .evening: "A check-in each evening at 8"
            case .sunday: "A recap of your week, Sunday evenings"
            case .needed: "Only notifying you when something needs you"
            }
        }
        /// When the repeating notification fires. Nil for "only when needed".
        var time: DateComponents? {
            switch self {
            case .morning: DateComponents(hour: 8, minute: 0)
            case .evening: DateComponents(hour: 20, minute: 0)
            case .sunday: DateComponents(hour: 18, minute: 0, weekday: 1)
            case .needed: nil
            }
        }
    }

    // MARK: Stored answers

    static func goals(_ raw: String) -> Set<Goal> {
        Set(raw.split(separator: ",").compactMap { Goal(rawValue: String($0)) })
    }

    static func raw(_ goals: Set<Goal>) -> String {
        Goal.allCases.filter(goals.contains).map(\.rawValue).joined(separator: ",")
    }
}

/// The check-in the person picked during setup: one repeating, local
/// notification. It says nothing about amounts (it's written ahead of time),
/// just invites a look.
enum CheckInReminder {
    static let id = "sortd.checkin"

    static func schedule(_ choice: SetupProfile.CheckIn) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let time = choice.time else { return }
        let content = UNMutableNotificationContent()
        switch choice {
        case .morning:
            content.title = "Yesterday, sorted"
            content.body = "Take a quick look at what you spent."
        case .evening:
            content.title = "Today, sorted"
            content.body = "Anything to fix before the day ends?"
        case .sunday:
            content.title = "Your week in Sortd"
            content.body = "Where it went, in one look."
        case .needed:
            return
        }
        content.userInfo = ["url": "sortd://activity"]
        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

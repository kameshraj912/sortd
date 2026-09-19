import Foundation
import UserNotifications

/// Local notifications the day before a predicted payment. Nothing leaves
/// the phone. Rebuilt each time the app opens, so they follow the latest
/// predictions and Raj's cancellations.
@MainActor
enum Reminders {
    static let enabledKey = "paymentReminders"
    private static let prefix = "recurring-"

    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Asks once; returns whether reminders are allowed.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func reschedule(_ recurring: [Recurring], now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        guard enabled else { return }

        let cal = Calendar.current
        let horizon = cal.date(byAdding: .day, value: 45, to: now)!
        // iOS keeps at most 64 pending; stay well under.
        for r in recurring.filter({ $0.status == .active && $0.nextDate <= horizon }).prefix(40) {
            guard let dayBefore = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: r.nextDate)),
                  let fireAt = cal.date(bySettingHour: 9, minute: 0, second: 0, of: dayBefore),
                  fireAt > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = "\(r.merchant) tomorrow"
            content.body = "\(Money.format(r.amount, r.currency)) on \(r.card.shortLabel). \(r.cadence.name)."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: prefix + r.key, content: content, trigger: trigger))
        }
    }
}

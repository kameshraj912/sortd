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
        // Reminders are part of Subscriptions & bills (Pro). A lapsed
        // subscription stops them; the setting comes back with Pro.
        guard enabled, ProStore.shared.isPro else { return }

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
    // MARK: Free trial

    /// Whether the paywall can promise a reminder: false only when the
    /// person has turned notifications off for Sortd.
    static func canPromiseReminder() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus != .denied
    }

    /// "Your trial ends in 2 days", at 9 am two days before the end. Asks for
    /// permission first (the trial timeline said Sortd would). Separate from
    /// the bill reminders setting: it was promised at purchase.
    static func scheduleTrialEnding(endsAt end: Date, price: String, now: Date = .now) async {
        guard let fireAt = TrialReminder.fireDate(trialEnd: end, now: now),
              await requestPermission() else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [TrialReminder.id])
        let content = UNMutableNotificationContent()
        content.title = "Your Sortd Pro trial ends in \(TrialTimeline.reminderDaysBefore) days"
        content.body = "If you keep Pro, \(price) starts on \(end.formatted(.dateTime.weekday(.wide).day().month(.wide))). To stop, cancel in Settings › Apple Account › Subscriptions."
        content.sound = .default
        let cal = Calendar.current
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt), repeats: false)
        try? await center.add(UNNotificationRequest(identifier: TrialReminder.id, content: content, trigger: trigger))
    }

    // MARK: Category limits

    private static let limitPrefix = "category-limit-"

    /// A notification when a category first passes 80% and 100% of its
    /// monthly limit. Only when reminders are on; each one fires once a month.
    static func checkCategoryLimits(_ transactions: [Transaction], now: Date = .now,
                                    defaults: UserDefaults = .standard) async {
        guard enabled, ProStore.shared.isPro else { return }
        let progress = CategoryBudgets.progress(for: transactions, limits: CategoryBudgets.all(defaults), now: now)
        let due = CategoryBudgets.dueAlerts(progress, month: CategoryBudgets.monthKey(now),
                                            sent: CategoryBudgets.sentAlerts(defaults))
        CategoryBudgets.saveSentAlerts(due.sent, defaults)

        let center = UNUserNotificationCenter.current()
        for alert in due.alerts {
            let name = alert.category.name
            let p = alert.progress
            let limit = Money.format(Decimal(p.limit), Money.home, cents: false)
            let content = UNMutableNotificationContent()
            switch alert.threshold {
            case .near:
                content.title = "\(name) is near its limit"
                content.body = "\(Money.format(Decimal(p.spent), Money.home, cents: false)) of \(limit) spent. \(Money.format(Decimal(p.left), Money.home, cents: false)) left this month."
            case .over:
                content.title = "\(name) is over its limit"
                content.body = "\(Money.format(Decimal(-p.left), Money.home, cents: false)) over your \(limit) limit this month."
            }
            content.sound = .default
            let id = limitPrefix + CategoryBudgets.alertKey(month: CategoryBudgets.monthKey(now),
                                                             category: alert.category, threshold: alert.threshold)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }
}

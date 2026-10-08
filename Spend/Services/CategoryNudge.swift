import Foundation
import SwiftData
import UserNotifications

/// The nudge after a Wallet tap (8 Oct 2026): when the tap moves its
/// category past 80% or 100% of the monthly limit, a second notification
/// follows "Logged", for example "Transport is near its limit" /
/// "Transport this month: $180 of $200 · $20 left".
///
/// Why a second notice and not more words on "Logged": "Logged" is a quiet
/// receipt for every tap and can be turned off on its own; the limit alert
/// is rare and is the one worth reading. Keeping them apart lets each have
/// its own switch and keeps "Logged" short.
///
/// Before this, limit alerts only ran when the app came to the foreground
/// (`Reminders.checkCategoryLimits`), and only with the bills reminders on.
/// Both paths share one record (`CategoryBudgets.sentAlerts`) and one
/// notification identifier, so a crossing is announced once either way.
///
/// At most 3 nudges in any 7 days (docs/ux-research/03-retention-research.md
/// §8 #7: a hard cap of 3 pushes a week, not counting "Logged"). Past the
/// cap the crossing is still recorded, so it is not sent later either.
enum CategoryNudge {
    /// Settings › Bills & Reminders › Category Limit Alerts. On by default.
    nonisolated static let enabledKey = "categoryLimitAlerts"

    static func isOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    /// When each nudge was sent, for the weekly cap.
    nonisolated static let datesKey = "categoryNudgeDates"
    nonisolated static let weeklyCap = 3

    /// True when fewer than `weeklyCap` nudges went out in the 7 days before `now`.
    nonisolated static func underWeeklyCap(dates: [Date], now: Date) -> Bool {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        return dates.filter { $0 > weekAgo }.count < weeklyCap
    }

    /// The alert this purchase makes due, if any, and the updated record.
    /// Only the purchase's own category is checked. Nil (record unchanged)
    /// when that category has no limit or is a transfer. Pure.
    static func due(for transaction: Transaction, in all: [Transaction], limits: [SpendCategory: Double],
                    sent: Set<String>, now: Date, calendar: Calendar = .current)
        -> (alert: CategoryBudgets.Alert?, sent: Set<String>) {
        let category = transaction.category
        guard category != .transfers, let limit = limits[category] else { return (nil, sent) }
        let progress = CategoryBudgets.progress(for: all, limits: [category: limit], now: now, calendar: calendar)
        let due = CategoryBudgets.dueAlerts(progress, month: CategoryBudgets.monthKey(now, calendar: calendar), sent: sent)
        return (due.alerts.first, due.sent)
    }

    /// After a real run (`LogWalletTapIntent.performRun`), right after
    /// "Logged". Does nothing unless the run saved a purchase, the switch is
    /// on and notifications are already allowed (this never asks). Nothing is
    /// recorded until those gates pass.
    static func post(for outcome: LogPurchaseIntent.Outcome, in context: ModelContext, now: Date,
                     defaults: UserDefaults = .standard) async {
        guard case .purchase = LoggedNotice.saved(from: outcome), let transaction = outcome.transaction,
              isOn(defaults), await LoggedNotice.notificationsAllowed() else { return }

        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let result = due(for: transaction, in: all, limits: CategoryBudgets.all(defaults),
                         sent: CategoryBudgets.sentAlerts(defaults), now: now)
        guard let alert = result.alert else { return }
        CategoryBudgets.saveSentAlerts(result.sent, defaults)

        let dates = defaults.array(forKey: datesKey) as? [Date] ?? []
        guard underWeeklyCap(dates: dates, now: now) else { return }
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        defaults.set(dates.filter { $0 > weekAgo } + [now], forKey: datesKey)

        let content = UNMutableNotificationContent()
        content.title = CategoryBudgets.title(for: alert.category, alert.threshold)
        content.body = CategoryBudgets.statusLine(alert.category, alert.progress)
        content.interruptionLevel = .active
        content.sound = .default
        content.userInfo = ["url": "sortd://insights"]
        let id = "category-limit-" + CategoryBudgets.alertKey(month: CategoryBudgets.monthKey(now),
                                                                category: alert.category, threshold: alert.threshold)
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

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
/// Both paths now share one switch, one record (`CategoryBudgets.sentAlerts`),
/// one weekly cap and one sender (`send`), so a crossing is announced once.
///
/// At most 3 in any 7 days, counting both paths (docs/ux-research/
/// 03-retention-research.md §8 #7: a hard cap of 3 pushes a week, not
/// counting "Logged"). Past the cap the crossing is still recorded, so it
/// is not sent later either.
enum CategoryNudge {
    /// Settings › Bills & Reminders › Category Limit Alerts. On by default.
    nonisolated static let enabledKey = "categoryLimitAlerts"

    static func isOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    /// When each limit alert was posted, for the weekly cap.
    nonisolated static let datesKey = "categoryNudgeDates"
    nonisolated static let weeklyCap = 3

    /// The dates in the 7 days up to `now`. Older ones and any in the
    /// future (the clock moved back) are dropped.
    nonisolated static func recent(_ dates: [Date], now: Date) -> [Date] {
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        return dates.filter { $0 > weekAgo && $0 <= now }
    }

    /// True when fewer than `weeklyCap` alerts went out in the 7 days before `now`.
    nonisolated static func underWeeklyCap(dates: [Date], now: Date) -> Bool {
        recent(dates, now: now).count < weeklyCap
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
    /// on, the purchase's category has a limit and notifications are already
    /// allowed (this never asks). Nothing is recorded until those gates pass.
    /// `allowed` is there for tests; the app uses the real permission.
    static func post(for outcome: LogPurchaseIntent.Outcome, in context: ModelContext, now: Date,
                     defaults: UserDefaults = .standard,
                     allowed: () async -> Bool = LoggedNotice.notificationsAllowed) async {
        let limits = CategoryBudgets.all(defaults)
        guard case .purchase = LoggedNotice.saved(from: outcome), let transaction = outcome.transaction,
              isOn(defaults), limits[transaction.category] != nil, await allowed() else { return }

        let all = (try? context.fetch(FetchDescriptor<Transaction>())) ?? []
        let result = due(for: transaction, in: all, limits: limits,
                         sent: CategoryBudgets.sentAlerts(defaults), now: now)
        guard let alert = result.alert else { return }
        CategoryBudgets.saveSentAlerts(result.sent, defaults)
        await send(alert, now: now, defaults: defaults)
    }

    /// Posts one alert while under the weekly cap and notes the date; past
    /// the cap it does nothing. Used by both paths; the caller has already
    /// recorded the crossing and checked the permission.
    static func send(_ alert: CategoryBudgets.Alert, now: Date, defaults: UserDefaults) async {
        let dates = defaults.array(forKey: datesKey) as? [Date] ?? []
        guard underWeeklyCap(dates: dates, now: now) else { return }
        defaults.set(recent(dates, now: now) + [now], forKey: datesKey)
        try? await UNUserNotificationCenter.current().add(request(for: alert, now: now))
    }

    /// The notification for one alert. Tapping it opens Insights.
    static func request(for alert: CategoryBudgets.Alert, now: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = CategoryBudgets.title(for: alert.category, alert.threshold)
        content.body = CategoryBudgets.statusLine(alert.category, alert.progress)
        content.interruptionLevel = .active
        content.sound = .default
        content.userInfo = ["url": "sortd://insights"]
        let id = CategoryBudgets.notificationID(month: CategoryBudgets.monthKey(now),
                                                category: alert.category, threshold: alert.threshold)
        return UNNotificationRequest(identifier: id, content: content, trigger: nil)
    }
}

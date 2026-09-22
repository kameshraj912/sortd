import Foundation
import SwiftData
import WidgetKit

/// Keeps the widget's numbers the same as the app's.
///
/// A widget that disagrees with the app it came from is worse than no
/// widget, so the sums here mirror `HomeView.budgetLine` exactly: money
/// left is the budget minus this month's spending, and the daily figure
/// takes off the bills that haven't charged yet.
@MainActor
enum WidgetBridge {

    private static var pending: Task<Void, Never>?
    /// Bulk imports (a Gmail sync) save every second or so. Each save would
    /// rebuild the summary and reload the widget, which WidgetKit budgets.
    /// While held, saves only mark the widget stale; `release` refreshes once.
    private static var holds = 0
    private static var stale = false

    static func hold() { holds += 1 }

    static func release() {
        holds = max(0, holds - 1)
        guard holds == 0, stale else { return }
        stale = false
        refresh(from: SpendStore.container.mainContext)
    }

    /// Refreshes the widget after every save to the store: a tap logged by
    /// Shortcuts, a purchase added, edited or deleted, an import, a restore.
    /// Call once at launch. Saves close together are batched.
    static func watchSaves() {
        let context = SpendStore.container.mainContext
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context, queue: .main) { _ in
            MainActor.assumeIsolated {
                if holds > 0 { stale = true; return }
                pending?.cancel()
                pending = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    refresh(from: context)
                }
            }
        }
    }

    /// Rebuilds the summary and asks the widget to redraw.
    /// Safe to call often and safe to call when there is no App Group.
    static func refresh(from context: ModelContext,
                        now: Date = .now,
                        calendar: Calendar = .current) {
        guard WidgetSummary.fileURL != nil else { return }
        let span = Perf.begin("widget.refresh")
        defer { span.end() }
        guard let all = try? context.fetch(FetchDescriptor<Transaction>()) else { return }
        let summary = build(from: all, now: now, calendar: calendar)
        guard summary.write() else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Pure, so it can be tested without a widget or a container.
    static func build(from transactions: [Transaction],
                      budget: Double = UserDefaults.standard.double(forKey: "monthlyBudget"),
                      now: Date = .now,
                      calendar: Calendar = .current) -> WidgetSummary {
        var out = WidgetSummary()
        out.updatedAt = now
        out.currency = Money.home
        out.hasAnyPurchases = !transactions.isEmpty

        let live = transactions.filter { !$0.refunded }

        let startOfDay = calendar.startOfDay(for: now)
        out.today = live
            .filter { calendar.isDate($0.date, inSameDayAs: startOfDay) }
            .reduce(Decimal(0)) { $0 + $1.audValue }

        let month = calendar.dateInterval(of: .month, for: now)
        let monthItems = live.filter { month?.contains($0.date) ?? false }
        out.month = monthItems.reduce(Decimal(0)) { $0 + $1.audValue }

        if budget > 0 {
            let left = Decimal(budget) - out.month
            out.leftThisMonth = left
            if left > 0 {
                let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
                let daysLeft = max(1, daysInMonth - calendar.component(.day, from: now) + 1)
                // Bills still to charge this month are already spoken for.
                let monthEnd = month?.end ?? now
                let bills = transactions.recurring()
                    .filter { $0.status == .active && $0.nextDate < monthEnd }
                    .reduce(Decimal(0)) { $0 + $1.audAmount }
                let spendable = max(0, left - bills)
                out.perDay = spendable / Decimal(daysLeft)
            } else {
                out.perDay = 0
            }
        }

        out.budget = budget > 0 ? Decimal(budget) : nil
        out.style = UserDefaults.standard.string(forKey: "cardStyle") ?? "satin"
        out.showWhenLocked = UserDefaults.standard.bool(forKey: WidgetSummary.showWhenLockedKey)

        // Monday to now. Finance widgets that only show a daily number read
        // as a telling-off on a bad day; a week is easier to live with.
        if let week = calendar.dateInterval(of: .weekOfYear, for: now) {
            out.week = live.filter { week.contains($0.date) }
                .reduce(Decimal(0)) { $0 + $1.audValue }
        }

        // What one day is worth, so "today" can be shown against a limit.
        if budget > 0 {
            let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
            out.dayAllowance = Decimal(budget) / Decimal(daysInMonth)
        }

        // Biggest categories this month, for the breakdown widget.
        var totals: [SpendCategory: Decimal] = [:]
        for t in monthItems { totals[t.category, default: 0] += t.audValue }
        out.categories = totals
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { WidgetSummary.Slice(category: $0.key.rawValue, name: $0.key.name, total: $0.value) }

        // What's charging next.
        out.bills = transactions.recurring(now: now)
            .filter { $0.status == .active && $0.nextDate >= calendar.startOfDay(for: now) }
            .sorted { $0.nextDate < $1.nextDate }
            .prefix(4)
            .map { WidgetSummary.Bill(name: $0.merchant, amount: $0.audAmount,
                                      currency: out.currency, due: $0.nextDate) }

        // No recent purchases: no widget shows them, so they aren't written
        // into the shared file at all.

        return out
    }
}

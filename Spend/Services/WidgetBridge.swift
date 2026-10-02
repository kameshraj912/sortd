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

        // Same rule as Home's `audTotal`: refunds and transfers (a top-up,
        // money moved between your own accounts) aren't spending.
        let live = transactions.filter { !$0.refunded && $0.category != .transfers }

        let startOfDay = calendar.startOfDay(for: now)
        let todayItems = live.filter { calendar.isDate($0.date, inSameDayAs: startOfDay) }
        out.today = todayItems.audTotal
        out.todayCount = todayItems.count

        let month = calendar.dateInterval(of: .month, for: now)
        let monthItems = live.filter { month?.contains($0.date) ?? false }
        out.month = monthItems.audTotal

        if budget > 0 {
            let left = Decimal(budget) - out.month
            out.leftThisMonth = left
            if left > 0 {
                let daysInMonth = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
                let daysLeft = max(1, daysInMonth - calendar.component(.day, from: now) + 1)
                // Bills still to charge this month are already spoken for.
                let monthEnd = month?.end ?? now
                let bills = transactions.recurring(now: now).stillToCharge(before: monthEnd, calendar: calendar)
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
            out.week = live.filter { week.contains($0.date) }.audTotal
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
            .filter { $0.value > 0 }
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

        // The last three purchases. History: this was left empty on purpose
        // (no widget showed purchases, so shop names stayed out of the shared
        // file). On 2 Oct 2026 Raj approved the Recent and Today widgets and
        // reversed that: shop names MAY be in widgets. The rule now is that
        // the widgets hide shop names AND amounts while the iPhone is locked
        // (`.privacySensitive()`), and shop names are hidden even when
        // "Show Amounts When Locked" is on. The file itself is still only
        // readable by Sortd and its widgets, on the phone.
        out.recent = recentItems(from: transactions, currency: out.currency)

        return out
    }
}

// MARK: - Recent purchases

extension WidgetBridge {
    /// How many purchases the Recent widget has room for.
    static let recentLimit = 3

    /// Newest first. Left out: the rows Activity hides (the old test tap and
    /// the Apple Pay health check), refunds and transfers (not purchases,
    /// same rule as the totals), and taps that landed with no shop name or no
    /// amount, which have nothing sensible to show and read as "Needs a
    /// check" in the app.
    ///
    /// The amount is in the home currency, as Home and Insights total it. A
    /// purchase still waiting on its exchange rate keeps its own currency.
    static func recentItems(from transactions: [Transaction], currency home: String) -> [WidgetSummary.Item] {
        let hidden = [LogPurchaseIntent.legacyTestMerchant, ApplePayHealthCheck.merchant]
        return transactions
            .filter { t in
                !t.refunded && t.category != .transfers
                    && !hidden.contains(t.merchant) && !hidden.contains(t.rawMerchant)
                    && !t.merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !t.needsReview
            }
            .sorted { $0.date > $1.date }
            .prefix(recentLimit)
            .map { t in
                let converted = t.audAmount != nil || t.currencyCode == home
                return WidgetSummary.Item(
                    id: t.id,
                    merchant: t.merchant.trimmingCharacters(in: .whitespacesAndNewlines),
                    amount: converted ? (t.audAmount ?? t.amount) : t.amount,
                    currency: converted ? home : t.currencyCode,
                    category: t.categoryRaw,
                    date: t.date)
            }
    }
}

// MARK: - Bills still to charge

extension Recurring {
    /// How many times this charges from `nextDate` up to (not including)
    /// `end`. A weekly bill can land four or five times in what's left of a
    /// month; a monthly one at most once.
    func timesDue(before end: Date, calendar: Calendar = .current) -> Int {
        guard status == .active else { return 0 }
        var count = 0
        var date = nextDate
        while date < end, count < 60 {
            count += 1
            date = cadence.advance(nextDate, by: count, calendar: calendar)
        }
        return count
    }
}

extension Array where Element == Recurring {
    /// What active bills will still take before `end`, in the home currency,
    /// counting each time a weekly or fortnightly one falls. Home's "a day"
    /// figure and the widget both use this, so they agree.
    func stillToCharge(before end: Date, calendar: Calendar = .current) -> Decimal {
        reduce(Decimal(0)) { $0 + $1.audAmount * Decimal($1.timesDue(before: end, calendar: calendar)) }
    }
}

import Testing
import Foundation
import SwiftData
@testable import Spend

/// The nudge after a Wallet tap: when the tap moves a category past 80% or
/// 100% of its monthly cap, a second notification follows "Logged".
/// `due` is pure and decides everything; `post` only adds the gates
/// (switch, permission, weekly cap) and the OS call.
@MainActor
struct CategoryNudgeTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let day: TimeInterval = 86_400

    private func suite() -> UserDefaults { UserDefaults(suiteName: "nudge-\(UUID().uuidString)")! }

    private func m(_ x: Double) -> String { Money.format(Decimal(x), Money.home, cents: false) }

    private func key(_ category: SpendCategory, _ threshold: CategoryBudgets.Threshold) -> String {
        CategoryBudgets.alertKey(month: CategoryBudgets.monthKey(now), category: category, threshold: threshold)
    }

    /// Built by hand in the home currency, so `audAmount` is set.
    private func txn(_ amount: Decimal, _ category: SpendCategory = .transport, ago: TimeInterval = 3_600) -> Transaction {
        Transaction(date: now.addingTimeInterval(-ago), merchant: "Shop", amount: amount, currencyCode: Money.home,
                    card: .other, category: category, source: .tap)
    }

    private func foreign(_ amount: Decimal, aud: Decimal?, _ category: SpendCategory = .transport) -> Transaction {
        let code = Money.home == "USD" ? "EUR" : "USD"
        let t = Transaction(date: now.addingTimeInterval(-60), merchant: "Shop", amount: amount, currencyCode: code,
                            card: .other, category: category, source: .tap)
        t.audAmount = aud
        return t
    }

    private func due(_ this: Transaction, _ prior: [Transaction], limits: [SpendCategory: Double],
                     sent: Set<String> = []) -> (alert: CategoryBudgets.Alert?, sent: Set<String>) {
        CategoryNudge.due(for: this, in: prior + [this], limits: limits, sent: sent, now: now, calendar: .current)
    }

    // MARK: - What is due

    @Test func noCapGivesNoAlert() {
        let r = due(txn(23), [], limits: [:], sent: ["x|y|80"])
        #expect(r.alert == nil)
        #expect(r.sent == ["x|y|80"])
    }

    @Test func underEightyPercentGivesNoAlert() {
        #expect(due(txn(23), [txn(100)], limits: [.transport: 200]).alert == nil)
    }

    @Test func crossingEightyPercentIsNear() throws {
        let r = due(txn(30), [txn(150)], limits: [.transport: 200])
        let alert = try #require(r.alert)
        #expect(alert.category == .transport)
        #expect(alert.threshold == .near)
        #expect(alert.progress.spent == 180)
        #expect(alert.progress.limit == 200)
        #expect(r.sent.contains(key(.transport, .near)))
    }

    @Test func crossingTheLimitIsOverAndRecordsBoth() throws {
        let r = due(txn(62), [txn(150)], limits: [.transport: 200])
        let alert = try #require(r.alert)
        #expect(alert.threshold == .over)
        #expect(alert.progress.spent == 212)
        #expect(r.sent.contains(key(.transport, .near)))
        #expect(r.sent.contains(key(.transport, .over)))
    }

    @Test func anAlreadyRecordedCrossingIsNil() {
        let sent: Set<String> = [key(.transport, .near)]
        let r = due(txn(30), [txn(150)], limits: [.transport: 200], sent: sent)
        #expect(r.alert == nil)
        #expect(r.sent == sent)
    }

    @Test func bothAtOnceIsOverOnly() throws {
        let r = due(txn(250), [], limits: [.transport: 200])
        let alert = try #require(r.alert)
        #expect(alert.threshold == .over)
        #expect(r.sent.contains(key(.transport, .near)))
        #expect(r.sent.contains(key(.transport, .over)))
    }

    @Test func aForeignPurchaseCountsItsHomeValue() throws {
        let converted = due(foreign(12, aud: 90), [txn(100)], limits: [.transport: 200])
        let alert = try #require(converted.alert)
        #expect(alert.threshold == .near)
        #expect(alert.progress.spent == 190)

        // No rate yet: it counts for nothing, so 100 of 200 is no alert.
        #expect(due(foreign(12, aud: nil), [txn(100)], limits: [.transport: 200]).alert == nil)
    }

    @Test func transfersAreNeverNudged() {
        let r = due(txn(500, .transfers), [], limits: [.transfers: 100])
        #expect(r.alert == nil)
    }

    @Test func otherCategoriesRecordsAreKept() throws {
        let eating = key(.eatingOut, .near)
        let r = due(txn(30), [txn(150)], limits: [.transport: 200], sent: [eating])
        #expect(try #require(r.alert).threshold == .near)
        #expect(r.sent.contains(eating))
        #expect(r.sent.contains(key(.transport, .near)))
    }

    @Test func otherCategoriesSpendDoesNotCount() {
        let r = due(txn(30), [txn(500, .groceries)], limits: [.transport: 200])
        #expect(r.alert == nil)
    }

    // MARK: - Weekly cap

    @Test func weeklyCapCountsTheLastSevenDays() {
        #expect(CategoryNudge.weeklyCap == 3)
        #expect(CategoryNudge.underWeeklyCap(dates: [], now: now))
        #expect(CategoryNudge.underWeeklyCap(dates: [now - day, now - 2 * day], now: now))
        #expect(!CategoryNudge.underWeeklyCap(dates: [now - day, now - 2 * day, now - 3 * day], now: now))
        // Three, but all 8+ days old.
        #expect(CategoryNudge.underWeeklyCap(dates: [now - 8 * day, now - 9 * day, now - 20 * day], now: now))
        // Two recent and one old.
        #expect(CategoryNudge.underWeeklyCap(dates: [now - day, now - 2 * day, now - 9 * day], now: now))
    }

    // MARK: - Words

    @Test func titleCopy() {
        #expect(CategoryBudgets.title(for: .transport, .near) == "Transport is near its limit")
        #expect(CategoryBudgets.title(for: .transport, .over) == "Transport is over its limit")
    }

    @Test func statusLineCopy() {
        let under = CategoryBudgets.statusLine(.transport, .init(spent: 180, limit: 200))
        #expect(under == "Transport this month: \(m(180)) of \(m(200)) · \(m(20)) left")
        let exact = CategoryBudgets.statusLine(.transport, .init(spent: 200, limit: 200))
        #expect(exact == "Transport this month: \(m(200)) of \(m(200)) · \(m(0)) left")
        let over = CategoryBudgets.statusLine(.transport, .init(spent: 212, limit: 200))
        #expect(over == "Transport this month: \(m(212)) of \(m(200)) · \(m(12)) over")
    }

    // MARK: - The switch

    @Test func switchDefaultsOn() {
        let d = suite()
        #expect(CategoryNudge.enabledKey == "categoryLimitAlerts")
        #expect(CategoryNudge.isOn(d))
        d.set(false, forKey: CategoryNudge.enabledKey)
        #expect(!CategoryNudge.isOn(d))
    }

    @Test func billsToggleDoesNotGateTheNudge() throws {
        let standard = UserDefaults.standard
        let was = standard.object(forKey: Reminders.enabledKey)
        standard.set(false, forKey: Reminders.enabledKey)
        defer {
            if let was { standard.set(was, forKey: Reminders.enabledKey) } else { standard.removeObject(forKey: Reminders.enabledKey) }
        }
        let r = due(txn(30), [txn(150)], limits: [.transport: 200])
        #expect(try #require(r.alert).threshold == .near)
    }

    // MARK: - post

    /// Notification permission is not granted in the test host, so `post`
    /// returns early anyway (see `FreeAppTests`); this pins that, with the
    /// switch off, nothing is recorded: not the alert, not the date.
    @Test func postRecordsNothingWhenOff() async throws {
        let container = try ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        ctx.insert(txn(150))
        try ctx.save()

        let d = suite()
        CategoryBudgets.set(200, for: .transport, d)
        d.set(false, forKey: CategoryNudge.enabledKey)

        let book = CardBook(defaults: suite())
        let r = try await LogWalletTapIntent.handle(nil, amount: Money.format(30, Money.home), merchant: "Uber",
                                                    card: "NAB Visa Debit", in: ctx, book: book, now: now)
        #expect(r.transaction != nil)

        await CategoryNudge.post(for: r, in: ctx, now: now, defaults: d)

        #expect(CategoryBudgets.sentAlerts(d).isEmpty)
        #expect((d.array(forKey: CategoryNudge.datesKey) ?? []).isEmpty)
    }
}

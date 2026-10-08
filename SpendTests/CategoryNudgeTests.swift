import Testing
import Foundation
import SwiftData
import UserNotifications
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
        // Over by less than the rounding: say "at its limit", not "$0 over".
        let hair = CategoryBudgets.statusLine(.transport, .init(spent: 200.3, limit: 200))
        #expect(hair == "Transport this month: \(m(200.3)) of \(m(200)) · at its limit")
    }

    // MARK: - The switch

    @Test func switchDefaultsOn() {
        let d = suite()
        #expect(CategoryNudge.enabledKey == "categoryLimitAlerts")
        #expect(CategoryNudge.isOn(d))
        d.set(false, forKey: CategoryNudge.enabledKey)
        #expect(!CategoryNudge.isOn(d))
    }

    // MARK: - post

    /// A real Wallet tap logged in an in-memory store, with 150 already
    /// spent in the tap's own category and a limit of 200 there, so the tap
    /// (30) crosses 80%. Asserts on the records (`sentAlerts`, the nudge
    /// dates): the test host cannot post a notification, so `allowed` is
    /// injected and the OS call itself is not checked.
    private func crossingTap(_ d: UserDefaults) async throws -> (LogPurchaseIntent.Outcome, ModelContext, SpendCategory) {
        let container = try ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        let r = try await LogWalletTapIntent.handle(nil, amount: Money.format(30, Money.home), merchant: "Uber",
                                                    card: "NAB Visa Debit", in: ctx, book: CardBook(defaults: suite()), now: now)
        let t = try #require(r.transaction)
        guard case .purchase = LoggedNotice.saved(from: r) else {
            Issue.record("the tap should log as a plain purchase")
            return (r, ctx, t.category)
        }
        ctx.insert(txn(150, t.category, ago: 7_200))
        try ctx.save()
        CategoryBudgets.set(200, for: t.category, d)
        return (r, ctx, t.category)
    }

    private func dates(_ d: UserDefaults) -> [Date] { d.array(forKey: CategoryNudge.datesKey) as? [Date] ?? [] }

    @Test func postRecordsNothingWhenTheSwitchIsOff() async throws {
        let d = suite()
        let (r, ctx, _) = try await crossingTap(d)
        d.set(false, forKey: CategoryNudge.enabledKey)

        await CategoryNudge.post(for: r, in: ctx, now: now, defaults: d, allowed: { true })

        #expect(CategoryBudgets.sentAlerts(d).isEmpty)
        #expect(dates(d).isEmpty)
    }

    @Test func postRecordsNothingWithoutPermission() async throws {
        let d = suite()
        let (r, ctx, _) = try await crossingTap(d)
        d.set(true, forKey: CategoryNudge.enabledKey)

        await CategoryNudge.post(for: r, in: ctx, now: now, defaults: d, allowed: { false })

        #expect(CategoryBudgets.sentAlerts(d).isEmpty)
        #expect(dates(d).isEmpty)
    }

    @Test func postAtTheWeeklyCapRecordsTheCrossingButNotADate() async throws {
        let d = suite()
        let (r, ctx, category) = try await crossingTap(d)
        let full = [now - day, now - 2 * day, now - 3 * day]
        d.set(full, forKey: CategoryNudge.datesKey)

        await CategoryNudge.post(for: r, in: ctx, now: now, defaults: d, allowed: { true })

        #expect(CategoryBudgets.sentAlerts(d).contains(key(category, .near)))
        #expect(dates(d) == full)
    }

    @Test func postUnderTheCapPrunesOldDatesAndAddsNow() async throws {
        let d = suite()
        let (r, ctx, category) = try await crossingTap(d)
        d.set([now - 10 * day], forKey: CategoryNudge.datesKey)

        await CategoryNudge.post(for: r, in: ctx, now: now, defaults: d, allowed: { true })

        #expect(CategoryBudgets.sentAlerts(d).contains(key(category, .near)))
        #expect(dates(d) == [now])
    }

    // MARK: - The foreground check shares the cap and the notification

    /// Four categories crossing at once (first open after the update) post
    /// at most three; all four are recorded so none comes back later.
    @Test func foregroundCheckSharesTheWeeklyCap() async {
        let d = suite()
        let cats: [SpendCategory] = [.transport, .groceries, .eatingOut, .shopping]
        for c in cats { CategoryBudgets.set(100, for: c, d) }
        let all = cats.map { txn(90, $0) }

        await Reminders.checkCategoryLimits(all, now: now, defaults: d, allowed: { true })

        for c in cats { #expect(CategoryBudgets.sentAlerts(d).contains(key(c, .near))) }
        #expect(dates(d) == [now, now, now])
    }

    @Test func foregroundCheckWithoutPermissionAddsNoDates() async {
        let d = suite()
        CategoryBudgets.set(100, for: .transport, d)
        await Reminders.checkCategoryLimits([txn(90)], now: now, defaults: d, allowed: { false })
        #expect(CategoryBudgets.sentAlerts(d).contains(key(.transport, .near)))
        #expect(dates(d).isEmpty)
    }

    /// One request builder, so the tap nudge and the foreground check can
    /// never announce the same crossing under two ids.
    @Test func bothPathsUseOneNotification() throws {
        let alert = CategoryBudgets.Alert(category: .transport, threshold: .near, progress: .init(spent: 180, limit: 200))
        let request = CategoryNudge.request(for: alert, now: now)
        #expect(request.identifier == "category-limit-" + key(.transport, .near))
        #expect(request.identifier == CategoryBudgets.notificationID(month: CategoryBudgets.monthKey(now),
                                                                     category: .transport, threshold: .near))
        #expect(request.content.userInfo["url"] as? String == "sortd://insights")
        #expect(request.content.interruptionLevel == .active)
        #expect(request.content.title == "Transport is near its limit")

        let services = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Spend/Services")
        // Both paths post through `CategoryNudge.send`, which builds the request above.
        let reminders = try String(contentsOf: services.appendingPathComponent("Reminders.swift"), encoding: .utf8)
        let nudge = try String(contentsOf: services.appendingPathComponent("CategoryNudge.swift"), encoding: .utf8)
        #expect(reminders.contains("await CategoryNudge.send("))
        #expect(!reminders.contains("\"category-limit-\""))
        #expect(nudge.contains("await send("))
    }
}

import Testing
import SwiftData
import Foundation
@testable import Spend

/// The numbers the widget shows. A widget that disagrees with the app it
/// came from is worse than no widget, so these pin the sums to the same
/// rules Home uses.
@MainActor
struct WidgetSummaryTests {

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private let cal = Calendar(identifier: .gregorian)

    private func at(_ ymd: String, _ hm: String = "12:00") -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = .current
        f.calendar = cal
        return f.date(from: "\(ymd) \(hm)")!
    }

    @discardableResult
    private func add(_ ctx: ModelContext, _ merchant: String, _ amount: Decimal, _ when: Date,
                     category: SpendCategory = .groceries) -> Transaction {
        let t = Transaction(date: when, merchant: merchant, amount: amount, currencyCode: Money.home,
                            card: .nab, category: category, source: .manual)
        ctx.insert(t)
        try? ctx.save()
        return t
    }

    // MARK: Totals

    @Test func todayIsOnlyToday() throws {
        let ctx = try store()
        let now = at("2026-09-15", "18:00")
        add(ctx, "Coffee", 5.50, at("2026-09-15", "08:00"))
        add(ctx, "Lunch", 18.00, at("2026-09-15", "13:00"))
        add(ctx, "Yesterday", 99.00, at("2026-09-14", "13:00"))

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let s = WidgetBridge.build(from: all, budget: 0, now: now, calendar: cal)

        #expect(s.today == Decimal(string: "23.50")!)
        #expect(s.month == Decimal(string: "122.50")!)
        #expect(s.hasAnyPurchases)
    }

    @Test func lastMonthIsNotThisMonth() throws {
        let ctx = try store()
        let now = at("2026-09-15")
        add(ctx, "August", 500.00, at("2026-08-31", "23:00"))
        add(ctx, "September", 10.00, at("2026-09-01", "01:00"))

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let s = WidgetBridge.build(from: all, budget: 0, now: now, calendar: cal)
        #expect(s.month == Decimal(10))
    }

    @Test func refundedPurchasesAreLeftOut() throws {
        let ctx = try store()
        let now = at("2026-09-15", "18:00")
        add(ctx, "Kept", 20.00, at("2026-09-15", "09:00"))
        let returned = add(ctx, "Returned", 80.00, at("2026-09-15", "10:00"))
        returned.refunded = true
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let s = WidgetBridge.build(from: all, budget: 0, now: now, calendar: cal)
        #expect(s.today == Decimal(20))
    }

    // MARK: Budget

    @Test func moneyLeftIsTheBudgetMinusThisMonth() throws {
        let ctx = try store()
        let now = at("2026-09-15", "18:00")
        add(ctx, "Shopping", 400.00, at("2026-09-10"))

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let s = WidgetBridge.build(from: all, budget: 1000, now: now, calendar: cal)
        #expect(s.leftThisMonth == Decimal(600))
    }

    @Test func goingOverBudgetGivesANegativeAndNoDailyFigure() throws {
        let ctx = try store()
        let now = at("2026-09-15", "18:00")
        add(ctx, "Shopping", 1200.00, at("2026-09-10"))

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let s = WidgetBridge.build(from: all, budget: 1000, now: now, calendar: cal)
        #expect(s.leftThisMonth == Decimal(-200))
        #expect(s.perDay == 0)
    }

    @Test func theDailyFigureSplitsWhatIsLeftOverTheDaysLeft() throws {
        let ctx = try store()
        // 15 September: 16 days left counting today, in a 30-day month.
        let now = at("2026-09-15", "18:00")
        add(ctx, "Shopping", 200.00, at("2026-09-10"))

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let s = WidgetBridge.build(from: all, budget: 1000, now: now, calendar: cal)
        #expect(s.leftThisMonth == Decimal(800))
        #expect(s.perDay == Decimal(50))  // 800 / 16
    }

    @Test func noBudgetMeansNoBudgetNumbers() throws {
        let ctx = try store()
        add(ctx, "Coffee", 5.50, at("2026-09-15", "08:00"))
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let s = WidgetBridge.build(from: all, budget: 0, now: at("2026-09-15", "18:00"), calendar: cal)
        #expect(s.leftThisMonth == nil)
        #expect(s.perDay == nil)
    }

    // MARK: Recent (see WidgetRecentTests)

    @Test func amountsAreHiddenWhenLockedUnlessTurnedOn() {
        var s = WidgetSummary()
        #expect(s.hidesWhenLocked)
        s.showWhenLocked = false
        #expect(s.hidesWhenLocked)
        s.showWhenLocked = true
        #expect(!s.hidesWhenLocked)
    }

    @Test func anEmptyStoreSaysSoRatherThanShowingZero() throws {
        let s = WidgetBridge.build(from: [], budget: 0, now: at("2026-09-15"), calendar: cal)
        #expect(!s.hasAnyPurchases)
        #expect(s.today == 0)
        #expect(s.recent.isEmpty)
    }

    // MARK: The file

    @Test func theSummarySurvivesBeingWrittenAndReadBack() throws {
        var s = WidgetSummary()
        s.currency = "SGD"
        s.today = Decimal(string: "23.50")!
        s.month = Decimal(string: "812.40")!
        s.leftThisMonth = Decimal(string: "187.60")!
        s.perDay = Decimal(string: "12.50")!
        s.hasAnyPurchases = true
        s.recent = [.init(merchant: "Seven Seeds", amount: 5.50, currency: "SGD",
                          category: "eatingOut", date: .now)]

        let url = FileManager.default.temporaryDirectory
            .appending(path: "summary-\(UUID().uuidString).json")
        #expect(s.write(to: url))

        let back = try #require(WidgetSummary.read(from: url))
        #expect(back.today == s.today)
        #expect(back.currency == "SGD")
        #expect(back.leftThisMonth == s.leftThisMonth)
        #expect(back.recent.first?.merchant == "Seven Seeds")
        try? FileManager.default.removeItem(at: url)
    }

    @Test func aMissingOrBrokenFileReadsAsNothingRatherThanCrashing() throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: "not-here.json")
        #expect(WidgetSummary.read(from: missing) == nil)
        #expect(WidgetSummary.decode(Data("nonsense".utf8)) == nil)
        #expect(WidgetSummary.read(from: nil) == nil)
    }

    // MARK: Stale file (bug hunt U1)

    @Test func afterMidnightTodayStartsAtZero() {
        var s = WidgetSummary()
        s.updatedAt = at("2026-09-21", "22:00")
        s.today = 40; s.week = 120; s.month = 500; s.perDay = 30
        let next = s.asOf(at("2026-09-22", "00:05"), calendar: cal)
        #expect(next.today == 0)
        #expect(next.perDay == nil)
        #expect(next.month == 500)          // same month: still true
    }

    @Test func aNewMonthStartsFromZero() {
        var s = WidgetSummary()
        s.updatedAt = at("2026-09-30", "20:00")
        s.today = 12; s.month = 812; s.budget = 1500; s.leftThisMonth = 688
        s.categories = [.init(category: "groceries", name: "Groceries", total: 300)]
        let next = s.asOf(at("2026-10-01", "08:00"), calendar: cal)
        #expect(next.month == 0)
        #expect(next.categories.isEmpty)
        #expect(next.leftThisMonth == 1500)
    }

    @Test func sameDayIsUnchanged() {
        var s = WidgetSummary()
        s.updatedAt = at("2026-09-21", "08:00")
        s.today = 40; s.month = 500
        #expect(s.asOf(at("2026-09-21", "21:00"), calendar: cal) == s)
    }
}

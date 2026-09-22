import Testing
import SwiftData
import Foundation
@testable import Spend

/// Money bugs from the September review: widget totals that counted
/// transfers, weekly bills taken off "a day" only once, and a currency change
/// that could convert the budget twice (or never).
@MainActor
struct MoneyFixesTests {

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

    private func bill(_ cadence: Cadence, next: Date, amount: Decimal = 50,
                      status: Recurring.Status = .active) -> Recurring {
        Recurring(key: "bill-\(cadence.rawValue)", merchant: "Bill", category: .bills, card: .nab,
                  cadence: cadence, amount: amount, currency: "AUD", audAmount: amount,
                  lastDate: cadence.advance(next, by: -1, calendar: cal), nextDate: next, charges: 3,
                  previousAmount: nil, status: status, chargedAfterCancel: false)
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "MoneyFixesTests-\(UUID().uuidString)")!
    }

    // MARK: Widget leaves out transfers, like Home

    @Test func widgetTotalsLeaveOutTransfers() throws {
        let ctx = try store()
        let now = at("2026-09-15", "18:00")
        add(ctx, "Coles", 20, at("2026-09-15", "09:00"))
        add(ctx, "Top up", 500, at("2026-09-15", "10:00"), category: .transfers)

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let s = WidgetBridge.build(from: all, budget: 1000, now: now, calendar: cal)
        #expect(s.today == 20)
        #expect(s.week == 20)
        #expect(s.month == 20)
        #expect(s.month == all.filter { $0.date >= at("2026-09-01", "00:00") }.audTotal)   // Home's sum
        #expect(s.leftThisMonth == 980)
        #expect(!s.categories.contains { $0.category == SpendCategory.transfers.rawValue })
    }

    // MARK: Bills still to charge this month

    @Test func weeklyAndFortnightlyBillsCountEachTimeTheyFall() {
        let monthEnd = at("2026-10-01", "00:00")
        let next = at("2026-09-16")
        #expect(bill(.weekly, next: next).timesDue(before: monthEnd, calendar: cal) == 3)       // 16, 23, 30
        #expect(bill(.fortnightly, next: next).timesDue(before: monthEnd, calendar: cal) == 2)  // 16, 30
        #expect(bill(.monthly, next: next).timesDue(before: monthEnd, calendar: cal) == 1)
        #expect(bill(.monthly, next: at("2026-10-03")).timesDue(before: monthEnd, calendar: cal) == 0)
        #expect(bill(.weekly, next: next, status: .lapsed).timesDue(before: monthEnd, calendar: cal) == 0)
        #expect(bill(.weekly, next: next, status: .cancelled).timesDue(before: monthEnd, calendar: cal) == 0)

        let bills = [bill(.weekly, next: next, amount: 50), bill(.monthly, next: next, amount: 20)]
        #expect(bills.stillToCharge(before: monthEnd, calendar: cal) == 170)   // 3 × 50 + 20
    }

    @Test func widgetDailyFigureTakesOffEveryWeeklyCharge() throws {
        let ctx = try store()
        // A weekly cleaner on Wednesdays: next due 16 Sep, then 23 and 30 Sep.
        for day in ["2026-08-26", "2026-09-02", "2026-09-09"] {
            add(ctx, "Sparkle Cleaning", 50, at(day), category: .other)
        }
        let now = at("2026-09-15", "18:00")
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        let s = WidgetBridge.build(from: all, budget: 1000, now: now, calendar: cal)

        #expect(s.leftThisMonth == 900)                        // 1000 − (2 Sep + 9 Sep)
        // 16 days left counting today; 3 more charges of 50 are spoken for.
        #expect(s.perDay == Decimal(750) / Decimal(16))
    }

    // MARK: Currency change

    @Test func twoRebasesAtOnceConvertTheBudgetOnce() async throws {
        let ctx = try store()
        let d = defaults()
        d.set("AUD", forKey: FXService.convertedKey)
        d.set("SGD", forKey: Money.homeKey)                    // the picker already saved it
        d.set(1000.0, forKey: FXService.budgetKey)
        d.set(["eatingOut": 300.0], forKey: CategoryBudgets.key)

        var calls = 0
        let slowRate: FXService.RateSource = { _, _ in
            calls += 1
            try await Task.sleep(for: .milliseconds(50))
            return 0.9
        }
        // Settings picker and app-open's safety net, while the rate downloads.
        let picker = Task { await FXService.rebase(to: "SGD", in: ctx, defaults: d, rate: slowRate) }
        let appOpen = Task { await FXService.ensureConverted(in: ctx, defaults: d, rate: slowRate) }
        await picker.value
        await appOpen.value

        #expect(d.double(forKey: FXService.budgetKey) == 900)
        #expect(CategoryBudgets.stored(d)["eatingOut"] == 270)
        #expect(d.string(forKey: FXService.convertedKey) == "SGD")
        #expect(calls == 1)
    }

    @Test func offlineLeavesTheBudgetToConvertNextTime() async throws {
        let ctx = try store()
        let d = defaults()
        d.set("AUD", forKey: FXService.convertedKey)
        d.set("SGD", forKey: Money.homeKey)
        d.set(1000.0, forKey: FXService.budgetKey)
        d.set(["eatingOut": 300.0], forKey: CategoryBudgets.key)

        await FXService.rebase(to: "SGD", in: ctx, defaults: d, rate: { _, _ in throw URLError(.notConnectedToInternet) })
        #expect(d.double(forKey: FXService.budgetKey) == 1000)
        #expect(CategoryBudgets.stored(d)["eatingOut"] == 300)
        #expect(d.string(forKey: FXService.convertedKey) == "AUD")    // not marked done
        #expect(d.string(forKey: Money.homeKey) == "SGD")

        // Back online: the next app open finishes the job.
        await FXService.ensureConverted(in: ctx, defaults: d, rate: { _, _ in 0.9 })
        #expect(d.double(forKey: FXService.budgetKey) == 900)
        #expect(CategoryBudgets.stored(d)["eatingOut"] == 270)
        #expect(d.string(forKey: FXService.convertedKey) == "SGD")
    }

    @Test func nothingToConvertIsDoneEvenOffline() async throws {
        let ctx = try store()
        let d = defaults()
        d.set("AUD", forKey: FXService.convertedKey)
        d.set("SGD", forKey: Money.homeKey)

        var calls = 0
        await FXService.rebase(to: "SGD", in: ctx, defaults: d, rate: { _, _ in
            calls += 1
            throw URLError(.notConnectedToInternet)
        })
        #expect(calls == 0)
        #expect(d.string(forKey: FXService.convertedKey) == "SGD")
    }

    @Test func aBudgetTypedWhileTheRateLoadsIsLeftAlone() async throws {
        let ctx = try store()
        let d = defaults()
        d.set("AUD", forKey: FXService.convertedKey)
        d.set("SGD", forKey: Money.homeKey)
        d.set(1000.0, forKey: FXService.budgetKey)

        await FXService.rebase(to: "SGD", in: ctx, defaults: d, rate: { _, _ in
            d.set(1234.0, forKey: FXService.budgetKey)          // typed in SGD meanwhile
            return 0.9
        })
        #expect(d.double(forKey: FXService.budgetKey) == 1234)
        #expect(d.string(forKey: FXService.convertedKey) == "SGD")
    }

    @Test func categoryLimitsConvertAndRoundToWholeAmounts() {
        let d = defaults()
        let before = ["eatingOut": 300.0, "groceries": 45.0, "transport": 500.0]
        d.set(before, forKey: CategoryBudgets.key)
        CategoryBudgets.set(420, for: .transport, d)             // changed while the rate loaded

        CategoryBudgets.convert(from: before, rate: 0.87, d)
        #expect(CategoryBudgets.all(d) == [.eatingOut: 261, .groceries: 39, .transport: 420])
    }
}

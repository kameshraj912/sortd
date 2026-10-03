import Testing
import Foundation
import SwiftData
@testable import Spend

/// Activity's one scrolling list (docs/specs/2026-10-03-activity-rebuild.md,
/// option B): grouping by day, day totals, search and filters across every
/// day at once, Undo, and "Go to Date…".
@MainActor
struct ActivityDaysTests {
    let context: ModelContext
    let cal: Calendar

    init() throws {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        self.cal = cal
    }

    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.startOfDay(for: at(y, m, d)) }

    /// Exact cents: a float literal like 31.40 isn't exactly 31.40 as a Decimal.
    func dec(_ s: String) -> Decimal { Decimal(string: s)! }

    /// A purchase in the in-memory store. `aud` is its home-currency value;
    /// it defaults to `amount` so totals don't depend on `Money.home`.
    @discardableResult
    func purchase(_ merchant: String, _ date: Date, amount: Decimal = 10, currency: String = "AUD",
                  aud: Decimal? = nil, card: Card = .nab, category: SpendCategory = .groceries,
                  note: String = "") throws -> Transaction {
        let t = Transaction(date: date, merchant: merchant, amount: amount, currencyCode: currency,
                            card: card, category: category, source: .manual, note: note)
        t.audAmount = aud ?? amount
        context.insert(t)
        try context.save()
        return t
    }

    // MARK: Grouping

    @Test func fivePurchasesOverThreeDaysMakeThreeDaysNewestFirst() throws {
        let a = try purchase("A", at(2026, 10, 1, 9))
        let b = try purchase("B", at(2026, 10, 1, 18))
        let c = try purchase("C", at(2026, 10, 2, 8))
        let d = try purchase("D", at(2026, 10, 3, 7))
        let e = try purchase("E", at(2026, 10, 3, 20))
        // Shuffled on purpose: the helper sorts, it doesn't trust the order.
        let days = ActivityDays.group([a, d, c, e, b], calendar: cal)
        #expect(days.map(\.date) == [day(2026, 10, 3), day(2026, 10, 2), day(2026, 10, 1)])
        #expect(days[0].items.map(\.merchant) == ["E", "D"])
        #expect(days[1].items.map(\.merchant) == ["C"])
        #expect(days[2].items.map(\.merchant) == ["B", "A"])
    }

    @Test func oneMinuteEitherSideOfMidnightIsTwoDays() throws {
        let late = try purchase("Late", at(2026, 10, 1, 23, 59))
        let early = try purchase("Early", at(2026, 10, 2, 0, 1))
        let days = ActivityDays.group([late, early], calendar: cal)
        #expect(days.count == 2)
        #expect(days.map(\.date) == [day(2026, 10, 2), day(2026, 10, 1)])
        #expect(days[0].items.map(\.merchant) == ["Early"])
        #expect(days[1].items.map(\.merchant) == ["Late"])
    }

    @Test func noPurchasesNoDays() {
        #expect(ActivityDays.group([], calendar: cal).isEmpty)
    }

    // MARK: Day total

    @Test func dayTotalSumsAUDValueAndLeavesOutTransfers() throws {
        let when = at(2026, 10, 2)
        let items = [
            try purchase("Woolworths", when, amount: 20),
            try purchase("Uber Eats", when.addingTimeInterval(60), amount: dec("31.40"), category: .foodDelivery),
            try purchase("NAB → YouTrip", when.addingTimeInterval(120), amount: 500, category: .transfers),
        ]
        let days = ActivityDays.group(items, calendar: cal)
        #expect(days.count == 1)
        #expect(days[0].total == dec("51.40"))
        // The same rule as every other total in the app.
        #expect(days[0].total == items.audTotal)
    }

    @Test func foreignPurchaseCountsByItsAUDValue() throws {
        let when = at(2026, 10, 2)
        let sgd = try purchase("Toast Box", when, amount: 10, currency: "SGD", aud: dec("11.62"))
        let aud = try purchase("Coles", when.addingTimeInterval(60), amount: 5)
        let days = ActivityDays.group([sgd, aud], calendar: cal)
        #expect(days[0].total == dec("16.62"))
    }

    // MARK: Search and filters

    @Test func searchFindsMatchesOnEveryDayAtOnce() throws {
        let all = [
            try purchase("Uber Eats", at(2026, 10, 3)),
            try purchase("Woolworths", at(2026, 10, 3, 14)),
            try purchase("Uber", at(2026, 10, 2), category: .transport),
            try purchase("Coles", at(2026, 10, 2, 15)),
            try purchase("Uber Eats", at(2026, 9, 28)),
        ]
        let shown = ActivityDays.visible(all, search: "uber")
        let days = ActivityDays.group(shown, calendar: cal)
        #expect(days.map(\.date) == [day(2026, 10, 3), day(2026, 10, 2), day(2026, 9, 28)])
        #expect(shown.allSatisfy { $0.merchant.hasPrefix("Uber") })
    }

    @Test func amountSearchMatchesThatAmountOrItsAUDValue() throws {
        let all = [
            try purchase("Uber Eats", at(2026, 10, 3), amount: dec("31.40")),
            try purchase("Starbucks", at(2026, 10, 3, 9), amount: dec("6.20")),
            try purchase("Toast Box", at(2026, 10, 2), amount: 27, currency: "SGD", aud: dec("31.40")),
            try purchase("Grill'd", at(2026, 10, 1), amount: dec("31.41")),
        ]
        let shown = ActivityDays.visible(all, search: "$31.40")
        #expect(Set(shown.map(\.merchant)) == ["Uber Eats", "Toast Box"])
    }

    @Test func categoryFilterAndSearchMustBothMatch() throws {
        let all = [
            try purchase("Uber Eats", at(2026, 10, 3), category: .foodDelivery),
            try purchase("Uber", at(2026, 10, 3, 9), category: .transport),
            try purchase("DoorDash", at(2026, 10, 2), category: .foodDelivery),
        ]
        let shown = ActivityDays.visible(all, category: .foodDelivery, search: "uber")
        #expect(shown.map(\.merchant) == ["Uber Eats"])
    }

    @Test func cardFilterShowsOnlyThatCard() throws {
        let all = [
            try purchase("Woolworths", at(2026, 10, 3), card: .nab),
            try purchase("Toast Box", at(2026, 10, 2), card: .youtrip),
            try purchase("Coles", at(2026, 10, 1), card: .nab),
        ]
        #expect(ActivityDays.visible(all, card: .youtrip).map(\.merchant) == ["Toast Box"])
        // A card's own list (from Home) filters the same way.
        #expect(ActivityDays.visible(all, fixedCard: .nab).map(\.merchant) == ["Woolworths", "Coles"])
    }

    @Test func noMatchesMeansNoDays() throws {
        let all = [try purchase("Woolworths", at(2026, 10, 3))]
        let shown = ActivityDays.visible(all, search: "zzz")
        #expect(shown.isEmpty)
        #expect(ActivityDays.group(shown, calendar: cal).isEmpty)
    }

    // MARK: Undo

    @Test func aRowWaitingOnUndoIsHiddenAndUndoPutsItBackInItsDay() throws {
        let keep = try purchase("Coles", at(2026, 10, 2, 9))
        let gone = try purchase("Woolworths", at(2026, 10, 2, 18))
        let other = try purchase("Grill'd", at(2026, 10, 1))
        let all = [gone, keep, other]
        let pending = PendingDeletes()
        pending.stage(gone) {}

        let hidden = Set(pending.items.map(\.persistentModelID))
        let during = ActivityDays.group(ActivityDays.visible(all, hidden: hidden), calendar: cal)
        #expect(during.map(\.date) == [day(2026, 10, 2), day(2026, 10, 1)])
        #expect(during[0].items.map(\.merchant) == ["Coles"])

        pending.undo()
        let after = ActivityDays.group(
            ActivityDays.visible(all, hidden: Set(pending.items.map(\.persistentModelID))), calendar: cal)
        #expect(after[0].items.map(\.merchant) == ["Woolworths", "Coles"])
    }

    // MARK: Go to Date

    var someDays: [Date] { [day(2026, 10, 3), day(2026, 9, 30), day(2026, 9, 25)] }

    @Test func goToADayWithPurchasesLandsOnThatDay() {
        #expect(ActivityDays.target(for: at(2026, 9, 30, 21), in: someDays, calendar: cal) == day(2026, 9, 30))
    }

    @Test func goToADayWithNoneLandsOnTheNearestOlderDay() {
        #expect(ActivityDays.target(for: at(2026, 10, 2), in: someDays, calendar: cal) == day(2026, 9, 30))
        #expect(ActivityDays.target(for: at(2026, 9, 27), in: someDays, calendar: cal) == day(2026, 9, 25))
    }

    @Test func goToBeforeTheOldestDayLandsOnTheOldest() {
        #expect(ActivityDays.target(for: at(2026, 1, 1), in: someDays, calendar: cal) == day(2026, 9, 25))
    }

    @Test func goToAfterTheNewestDayLandsOnTheNewest() {
        #expect(ActivityDays.target(for: at(2026, 12, 25), in: someDays, calendar: cal) == day(2026, 10, 3))
    }

    @Test func goToWithNoDaysGoesNowhere() {
        #expect(ActivityDays.target(for: at(2026, 10, 3), in: [], calendar: cal) == nil)
    }
}

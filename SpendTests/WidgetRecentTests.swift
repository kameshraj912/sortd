import Testing
import Foundation
@testable import Spend

/// The last three purchases and today's count, as written for the widgets.
///
/// Shop names are in the shared file from 2 Oct 2026 (Raj's decision: the
/// widgets may show them, and hide them while the iPhone is locked, which is
/// the widgets' job, not the file's). These pin what goes in and what stays
/// out, and that a file written by an older build still reads.
@MainActor
struct WidgetRecentTests {

    private let cal = Calendar(identifier: .gregorian)

    private func at(_ ymd: String, _ hm: String = "12:00") -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = .current
        f.calendar = cal
        return f.date(from: "\(ymd) \(hm)")!
    }

    private func tx(_ merchant: String, _ amount: Decimal, _ when: Date,
                    category: SpendCategory = .eatingOut,
                    currency: String = Money.home) -> Transaction {
        Transaction(date: when, merchant: merchant, amount: amount, currencyCode: currency,
                    card: .nab, category: category, source: .tap)
    }

    private func build(_ items: [Transaction], now: Date? = nil) -> WidgetSummary {
        WidgetBridge.build(from: items, budget: 0, now: now ?? at("2026-09-15", "18:00"), calendar: cal)
    }

    // MARK: Recent

    @Test func recentIsTheLastThreeNewestFirst() {
        let items = (1...6).map { tx("Shop \($0)", Decimal($0), at("2026-09-\(String(format: "%02d", $0))")) }
        let s = build(items.shuffled())
        #expect(s.recent.map(\.merchant) == ["Shop 6", "Shop 5", "Shop 4"])
    }

    @Test func fewerThanThreeShowsWhatExists() {
        #expect(build([tx("Only", 4, at("2026-09-15", "09:00"))]).recent.count == 1)
        #expect(build([]).recent.isEmpty)
    }

    @Test func recentCarriesTheFieldsTheWidgetNeeds() throws {
        let t = tx("Seven Seeds", Decimal(string: "5.50")!, at("2026-09-15", "08:30"), category: .eatingOut)
        let item = try #require(build([t]).recent.first)
        #expect(item.id == t.id)                 // the deep link opens this purchase
        #expect(item.merchant == "Seven Seeds")
        #expect(item.amount == Decimal(string: "5.50")!)
        #expect(item.currency == Money.home)
        #expect(item.category == "eatingOut")   // raw value, for the symbol and colour
        #expect(item.date == t.date)
    }

    @Test func recentGoesBackPastThisMonth() {
        let s = build([tx("Old", 3, at("2026-07-02"))])
        #expect(s.recent.map(\.merchant) == ["Old"])
    }

    @Test func aForeignPurchaseShowsInTheHomeCurrencyOnceConverted() throws {
        let other = Money.home == "SGD" ? "USD" : "SGD"
        let t = tx("Hawker", 10, at("2026-09-15", "09:00"), currency: other)
        t.audAmount = Decimal(string: "13.40")!   // `audAmount` holds the home-currency value
        let item = try #require(build([t]).recent.first)
        #expect(item.amount == Decimal(string: "13.40")!)
        #expect(item.currency == Money.home)
    }

    @Test func aForeignPurchaseStillWaitingOnARateKeepsItsOwnCurrency() throws {
        let other = Money.home == "SGD" ? "USD" : "SGD"
        let t = tx("Hawker", 10, at("2026-09-15", "09:00"), currency: other)
        t.audAmount = nil
        let item = try #require(build([t]).recent.first)
        #expect(item.amount == 10)
        #expect(item.currency == other)
    }

    @Test func hiddenTestAndHealthCheckRowsNeverShow() {
        let legacy = tx(LogPurchaseIntent.legacyTestMerchant, 1, at("2026-09-15", "11:00"))
        let check = tx(ApplePayHealthCheck.merchant, Decimal(string: "0.01")!, at("2026-09-15", "10:00"))
        let byRaw = tx("Sortd Check Store", 1, at("2026-09-15", "09:30"))
        byRaw.rawMerchant = ApplePayHealthCheck.merchant
        let real = tx("Real Cafe", 6, at("2026-09-15", "09:00"))
        #expect(build([legacy, check, byRaw, real]).recent.map(\.merchant) == ["Real Cafe"])
    }

    @Test func aRowThatNeedsACheckWithNoShopIsLeftOut() {
        let blank = tx("", 12, at("2026-09-15", "11:00"))
        blank.note = "\(Transaction.needsCheckTag)Apple Pay sent no shop name (Visa 1234). Tap to fix."
        let spaces = tx("   ", 7, at("2026-09-15", "10:00"))
        let real = tx("Real Cafe", 6, at("2026-09-15", "09:00"))
        #expect(build([blank, spaces, real]).recent.map(\.merchant) == ["Real Cafe"])
    }

    @Test func aTapWithNoAmountIsLeftOutBecauseThereIsNothingToShow() {
        let noAmount = tx("Mystery Shop", 0, at("2026-09-15", "11:00"))
        let real = tx("Real Cafe", 6, at("2026-09-15", "09:00"))
        #expect(build([noAmount, real]).recent.map(\.merchant) == ["Real Cafe"])
    }

    @Test func refundsAndTransfersAreNotPurchases() {
        let refunded = tx("Returned", 80, at("2026-09-15", "11:00")); refunded.refunded = true
        let topUp = tx("YouTrip top-up", 100, at("2026-09-15", "10:00"), category: .transfers)
        let real = tx("Real Cafe", 6, at("2026-09-15", "09:00"))
        #expect(build([refunded, topUp, real]).recent.map(\.merchant) == ["Real Cafe"])
    }

    @Test func aShopWithASpaceAroundItsNameIsTrimmed() throws {
        let item = try #require(build([tx("  Seven Seeds \n", 5, at("2026-09-15", "09:00"))]).recent.first)
        #expect(item.merchant == "Seven Seeds")
    }

    // MARK: Today's count

    @Test func todayCountIsOnlyTodaysPurchasesThatCountAsSpending() {
        let refunded = tx("Returned", 80, at("2026-09-15", "10:00")); refunded.refunded = true
        let items = [
            tx("A", 5, at("2026-09-15", "08:00")),
            tx("B", 6, at("2026-09-15", "13:00")),
            refunded,
            tx("Top-up", 50, at("2026-09-15", "14:00"), category: .transfers),
            tx("Yesterday", 9, at("2026-09-14", "13:00")),
        ]
        let s = build(items)
        #expect(s.todayCount == 2)
        #expect(s.today == 11)
    }

    @Test func todayCountIsZeroWhenNothingWasBoughtToday() {
        #expect(build([tx("Yesterday", 9, at("2026-09-14", "13:00"))]).todayCount == 0)
        #expect(build([]).todayCount == 0)
    }

    // MARK: Midnight

    @Test func afterMidnightTodayCountClearsButRecentStays() {
        var s = WidgetSummary()
        s.updatedAt = at("2026-09-21", "22:00")
        s.today = 40
        s.todayCount = 3
        s.recent = [.init(merchant: "Late Cafe", amount: 40, currency: "AUD", category: "eatingOut",
                          date: at("2026-09-21", "21:50"))]
        let next = s.asOf(at("2026-09-22", "00:05"), calendar: cal)
        #expect(next.todayCount == 0)
        #expect(next.today == 0)
        #expect(next.recent == s.recent)
    }

    @Test func sameDayKeepsTodayCount() {
        var s = WidgetSummary()
        s.updatedAt = at("2026-09-21", "08:00")
        s.todayCount = 2
        #expect(s.asOf(at("2026-09-21", "21:00"), calendar: cal).todayCount == 2)
    }

    // MARK: Day allowance and per-day across the calendar

    @Test func dayAllowanceFollowsTheNewMonthAcrossAYearEnd() {
        var s = WidgetSummary()
        s.updatedAt = at("2026-12-31", "20:00")
        s.budget = 310
        s.dayAllowance = 10
        let next = s.asOf(at("2027-01-01", "08:00"), calendar: cal)
        #expect(next.dayAllowance == 10)          // January has 31 days too
        #expect(next.perDay == nil)               // the daily figure waits for the app
    }

    @Test func dayAllowanceStaysPutWithinAMonth() {
        var s = WidgetSummary()
        s.updatedAt = at("2026-09-10", "08:00")
        s.budget = 300
        s.dayAllowance = 10
        #expect(s.asOf(at("2026-09-20", "08:00"), calendar: cal).dayAllowance == 10)
    }

    // MARK: Older files still read

    @Test func aFileFromAnOlderBuildStillDecodes() throws {
        // Exactly the keys an earlier build wrote: no `todayCount`, and an
        // empty `recent` (it never wrote purchases).
        let old = """
        {"updatedAt":"2026-09-15T08:00:00Z","currency":"AUD","today":12.5,"week":40,"month":812.4,
         "dayAllowance":50,"leftThisMonth":687.6,"perDay":45.84,"recent":[],
         "categories":[{"category":"groceries","name":"Groceries","total":312.1}],
         "bills":[],"budget":1500,"style":"satin","hasAnyPurchases":true,"showWhenLocked":false}
        """
        let s = try #require(WidgetSummary.decode(Data(old.utf8)))
        #expect(s.todayCount == 0)
        #expect(s.recent.isEmpty)
        #expect(s.today == Decimal(string: "12.5")!)
        #expect(s.budget == 1500)
        #expect(s.categories.count == 1)
        #expect(s.hasAnyPurchases)
    }

    @Test func aMinimalFileDecodesToDefaultsRatherThanFailing() throws {
        let s = try #require(WidgetSummary.decode(Data("{}".utf8)))
        #expect(s.todayCount == 0)
        #expect(s.recent.isEmpty)
        #expect(!s.hasAnyPurchases)
        #expect(s.currency == "AUD")
    }

    @Test func newFieldsSurviveBeingWrittenAndReadBack() throws {
        var s = WidgetSummary()
        s.todayCount = 4
        let id = UUID()
        s.recent = [.init(id: id, merchant: "Seven Seeds", amount: Decimal(string: "5.50")!, currency: "AUD",
                          category: "eatingOut", date: at("2026-09-15", "08:30"))]
        let back = try #require(WidgetSummary.decode(try s.encoded()))
        #expect(back.todayCount == 4)
        #expect(back.recent.first?.id == id)
        #expect(back.recent == s.recent)
    }
}

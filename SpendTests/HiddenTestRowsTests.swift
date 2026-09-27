import Testing
import Foundation
import SwiftData
@testable import Spend

/// Neither the removed "Send a Test Tap" button's rows
/// (`LogPurchaseIntent.legacyTestMerchant`, "Sortd Test") nor "Check the
/// Shortcut"'s own runs (`ApplePayHealthCheck.merchant`, "Sortd Check") may
/// ever reach Activity (any day, search or a card's own list), Home's
/// Recent list, Insights, budgets or totals, though the store still keeps
/// them — `ApplePayStatus` needs them there to settle status
/// (`ApplePayStatusTests`). One shared predicate does the hiding everywhere
/// those screens query from: `Transaction.excludingLegacyTest`.
@MainActor
struct HiddenTestRowsTests {
    let context: ModelContext

    init() throws {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    @Test func excludesTheTestRowFromTheGroupingHelperAndItsTotal() throws {
        let real = Transaction(date: .now, merchant: "Seven Seeds", amount: Decimal(string: "4.50")!,
                               currencyCode: "AUD", card: .other, category: .eatingOut, source: .tap)
        real.audAmount = real.amount   // a landed rate; audTotal doesn't depend on Money.home in this test
        let test = Transaction(date: .now, merchant: LogPurchaseIntent.legacyTestMerchant, amount: Decimal(string: "1.00")!,
                               currencyCode: "AUD", card: .other, category: .eatingOut, source: .tap)
        test.audAmount = test.amount
        context.insert(real)
        context.insert(test)
        try context.save()

        // Unfiltered: both rows are really in the store (ApplePayStatus still needs this).
        #expect(try context.fetch(FetchDescriptor<Transaction>()).count == 2)

        // What Activity/Home actually group and total (`ActivityView.days`,
        // `HomeView`'s month total): only the visible row.
        let visible = try context.fetch(FetchDescriptor<Transaction>(predicate: Transaction.excludingLegacyTest))
        #expect(visible.count == 1)
        #expect(visible.first?.merchant == "Seven Seeds")

        let days = Dictionary(grouping: visible) { Calendar.current.startOfDay(for: $0.date) }
        #expect(days.count == 1)
        #expect(days.values.first?.count == 1)
        #expect(visible.audTotal == Decimal(string: "4.50")!)
    }

    @Test func matchesOnEitherTheCleanedOrTheRawMerchant() throws {
        // A tap that arrived under the legacy test name but got cleaned
        // differently, or one only carrying it in `rawMerchant` — either
        // still hides.
        let byRaw = Transaction(date: .now, merchant: "Sortd Test Store", rawMerchant: LogPurchaseIntent.legacyTestMerchant,
                                amount: 1, currencyCode: "AUD", card: .other, category: .other, source: .tap)
        context.insert(byRaw)
        try context.save()
        let visible = try context.fetch(FetchDescriptor<Transaction>(predicate: Transaction.excludingLegacyTest))
        #expect(visible.isEmpty)
    }

    @Test func excludesTheHealthChecksOwnRowsToo() throws {
        let real = Transaction(date: .now, merchant: "Seven Seeds", amount: Decimal(string: "4.50")!,
                               currencyCode: "AUD", card: .other, category: .eatingOut, source: .tap)
        let check = Transaction(date: .now, merchant: ApplePayHealthCheck.merchant, amount: Decimal(string: "0.01")!,
                                currencyCode: "AUD", card: .other, category: .other, source: .tap)
        let checkByRaw = Transaction(date: .now, merchant: "Sortd Check Store", rawMerchant: ApplePayHealthCheck.merchant,
                                    amount: 1, currencyCode: "AUD", card: .other, category: .other, source: .tap)
        context.insert(real)
        context.insert(check)
        context.insert(checkByRaw)
        try context.save()

        // Unfiltered: every row is really in the store (ApplePayStatus still needs this).
        #expect(try context.fetch(FetchDescriptor<Transaction>()).count == 3)

        let visible = try context.fetch(FetchDescriptor<Transaction>(predicate: Transaction.excludingLegacyTest))
        #expect(visible.count == 1)
        #expect(visible.first?.merchant == "Seven Seeds")
    }

    @Test func statusStillSaysTheShortcutReachedAfterACheck() {
        // A "Check the Shortcut" run leaves a real row in the store (kept
        // for `ApplePayStatus`, hidden from every screen above), but it's
        // not a real tap: `ApplePayStatus.realTaps` excludes it the same
        // way it excludes the legacy test merchant, so the card still says
        // "Shortcut reached" from `lastReachedAt`, never "Last tap logged"
        // for the check's own A$0.01. Full coverage of the rule itself
        // lives in `ApplePayStatusTests`.
        let reached = Date(timeIntervalSince1970: 1_790_000_000)
        let checkRun = Transaction(date: reached, merchant: ApplePayHealthCheck.merchant,
                                  amount: Decimal(string: "0.01")!, currencyCode: "AUD",
                                  card: .other, category: .other, source: .tap)
        let status = ApplePayStatus.resolve(lastReachedAt: reached, taps: [checkRun])
        #expect(status == .shortcutReached(reached))
        #expect(status.title.hasPrefix("Shortcut reached Sortd"))
    }
}

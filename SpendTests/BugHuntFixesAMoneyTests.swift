import Testing
import Foundation
import SwiftData
@testable import Spend

/// Bug hunt 3 Oct 2026, fixed on `fix-hunt-a`: Currency signs and amounts in tap text (M2, M7, M8).
/// Each test failed before its fix. Helpers: `HuntA`.
@MainActor
struct BugHuntFixesAMoneyTests {

    private func store() throws -> ModelContext { try HuntA.store() }
    private func date(_ ymd: String, _ hm: String = "12:00") -> Date { HuntA.date(ymd, hm) }
    private func money(_ s: String) -> Decimal { HuntA.money(s) }
    private func calendar(_ id: Calendar.Identifier, _ zone: TimeZone = .current) -> Calendar { HuntA.calendar(id, zone) }
    private func ymd(_ d: Date?) -> String? { HuntA.ymd(d) }

    // MARK: M2. Every supported currency, as the phone writes it

    /// Formats 12.50 in every currency Sortd supports, the way an en_AU,
    /// en_SG, en_US or en_GB phone writes it (which is what a Wallet tap
    /// carries), and reads it back. The phone's own dollar is a bare "$",
    /// which names no currency (the tap takes the local one).
    @Test(arguments: ["en_AU", "en_SG", "en_US", "en_GB"])
    func everySupportedCurrencyIsReadBackAsThePhoneWritesIt(_ id: String) {
        let locale = Locale(identifier: id)
        var misses: [String] = []
        for code in Money.supported {
            let text = money("12.50").formatted(.currency(code: code).locale(locale))
            let sign = text.filter { !$0.isNumber && $0 != "." && $0 != "," && !$0.isWhitespace }
            let expected: String? = sign == "$" ? nil : code
            let parsed = AmountParser.parse(text)
            if parsed?.currency != expected { misses.append("\(code) \"\(text)\" read as \(parsed?.currency ?? "nil")") }
            if text.contains("12.50"), parsed?.amount != money("12.50") {
                misses.append("\(code) \"\(text)\" amount \(String(describing: parsed?.amount))")
            }
            // The Wallet reader must keep the sign with the number.
            let wallet = WalletTapText.money(in: "Shop \(text) NAB Visa Debit")
            if wallet.flatMap({ AmountParser.parse($0)?.currency }) != expected {
                misses.append("\(code) Wallet \"\(text)\" kept \(wallet ?? "nil")")
            }
        }
        #expect(misses.isEmpty, "\(id): \(misses.joined(separator: "; "))")
    }

    /// The finding's own cases.
    @Test func dollarSignsWithACountryPrefixAreRead() {
        #expect(AmountParser.parse("MX$500.00")?.currency == "MXN")
        #expect(AmountParser.parse("CA$12.50")?.currency == "CAD")
        #expect(AmountParser.parse("R$45.00")?.currency == "BRL")
        #expect(AmountParser.parse("NT$300")?.currency == "TWD")
        #expect(AmountParser.parse("₪45.00")?.currency == "ILS")
        #expect(WalletTapText.money(in: "Aroma ₪45.00 DBS Visa Debit").flatMap { AmountParser.parse($0)?.currency } == "ILS")
        // Unchanged: plain A$ and C$.
        #expect(AmountParser.parse("A$12.50")?.currency == "AUD")
        #expect(AmountParser.parse("C$12.50")?.currency == "CAD")
    }

    // MARK: M7. Rupees

    @Test func rsIsReadAsRupees() {
        #expect(AmountParser.parse("Rs500") == .init(amount: 500, currency: "INR"))
        #expect(AmountParser.parse("Rs 500") == .init(amount: 500, currency: "INR"))
        #expect(AmountParser.parse("Rs. 500") == .init(amount: 500, currency: "INR"))
        let wallet = WalletTapText.money(in: "Cafe Rs 500.00 DBS Visa Debit")
        #expect(wallet.flatMap { AmountParser.parse($0)?.currency } == "INR")
        // A shop called "RS ..." is not a currency.
        #expect(AmountParser.parse("RS Components 12.50")?.currency == nil)
        #expect(AmountParser.parse("HOURS 5")?.currency == nil)
    }

    // MARK: M8. A whole-dollar amount next to other digits

    @Test func aWholeDollarAmountIsNotJoinedToTheNextNumber() {
        #expect(WalletTapText.parse("Seven Seeds A$45 1234").amount.flatMap { AmountParser.parse($0)?.amount } == 45)
        #expect(AmountParser.parse("A$45 120")?.amount == 45)
        // Unchanged: spaced thousands with cents, and a no-break space.
        #expect(AmountParser.parse("1 234,56")?.amount == money("1234.56"))
        #expect(AmountParser.parse("12\u{00A0}345")?.amount == 12345)
        #expect(WalletTapText.money(in: "Cafe A$1,234.50 NAB") == "A$1,234.50")
    }
}

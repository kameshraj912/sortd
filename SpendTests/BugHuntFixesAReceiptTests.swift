import Testing
import Foundation
import SwiftData
@testable import Spend

/// Bug hunt 3 Oct 2026, fixed on `fix-hunt-a`: Receipt camera totals (M4, M5, M6).
/// Each test failed before its fix. Helpers: `HuntA`.
@MainActor
struct BugHuntFixesAReceiptTests {

    private func store() throws -> ModelContext { try HuntA.store() }
    private func date(_ ymd: String, _ hm: String = "12:00") -> Date { HuntA.date(ymd, hm) }
    private func money(_ s: String) -> Decimal { HuntA.money(s) }
    private func calendar(_ id: Calendar.Identifier, _ zone: TimeZone = .current) -> Calendar { HuntA.calendar(id, zone) }
    private func ymd(_ d: Date?) -> String? { HuntA.ymd(d) }

    // MARK: M4, M5, M6. Receipt camera totals

    @Test func aTotalWithACodeAndASignIsRead() {
        let a = ReceiptScanner.total(in: "PURCHASE AUD $45.00\nTOTAL AUD $45.00")
        #expect(a?.amount == "45.00")
        #expect(a?.currency == "AUD")
        let b = ReceiptScanner.total(in: "TOTAL AUD$45.00")
        #expect(b?.amount == "45.00")
        #expect(b?.currency == "AUD")
    }

    @Test func aTotalWithNoSignBeatsTheSubtotal() {
        #expect(ReceiptScanner.total(in: "SUBTOTAL $40.00\nGST $4.00\nTOTAL 44.00")?.amount == "44.00")
        #expect(ReceiptScanner.total(in: "SUB TOTAL $40.00\nGST $4.00\nTOTAL 44.00")?.amount == "44.00")
        // Unchanged: a signed total after a subtotal.
        #expect(ReceiptScanner.total(in: "SUBTOTAL $40.00\nTOTAL $44.00")?.amount == "44.00")
    }

    @Test func theCashHandedOverIsNotTheTotal() {
        #expect(ReceiptScanner.total(in: "TOTAL $45.00\nAMOUNT PAID $50.00\nCHANGE DUE $5.00")?.amount == "45.00")
        #expect(ReceiptScanner.total(in: "TOTAL $45.00\nCASH $50.00\nCHANGE $5.00")?.amount == "45.00")
        // Unchanged: on a card receipt "AMOUNT PAID" is the total.
        #expect(ReceiptScanner.total(in: "SUBTOTAL $40.00\nAMOUNT PAID $44.00")?.amount == "44.00")
    }
}

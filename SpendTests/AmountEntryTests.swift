import Testing
import Foundation
@testable import Spend

/// UI pass finding 12: the purchase detail's Amount field took 30 digits and
/// then quietly went back to the old value on leaving. Both the add sheet and
/// the detail now share one rule: refuse the key, keep what was there.
@MainActor
struct AmountEntryTests {

    @Test func thirtyDigitsAreRefusedAndTheLastValidTextStays() {
        let typed = String(repeating: "1", count: 30)
        #expect(!AmountEntry.isTypeable(typed))
        #expect(AmountEntry.accepted(typed, replacing: "31.40") == "31.40")
    }

    @Test func oneKeyPastTheLimitIsRefused() {
        // 999,999,999 is the most whole digits; a tenth is dropped.
        #expect(AmountEntry.accepted("123456789", replacing: "12345678") == "123456789")
        #expect(AmountEntry.accepted("1234567890", replacing: "123456789") == "123456789")
        // The add sheet stops at six.
        #expect(AmountEntry.accepted("1234567", replacing: "123456", wholeDigits: 6) == "123456")
        // Two decimals, never three.
        #expect(AmountEntry.accepted("31.40", replacing: "31.4") == "31.40")
        #expect(AmountEntry.accepted("31.405", replacing: "31.40") == "31.40")
    }

    @Test(arguments: ["abc", "31.4.0", "-5", "1,000,000", "31.40 "])
    func junkIsRefused(bad: String) {
        #expect(!AmountEntry.isTypeable(bad), "\(bad)")
        #expect(AmountEntry.accepted(bad, replacing: "5") == "5", "\(bad)")
    }

    @Test(arguments: ["", "5", "5.", "5,5", "0.01", "999999.99"])
    func normalTypingIsAccepted(ok: String) {
        #expect(AmountEntry.isTypeable(ok), "\(ok)")
        #expect(AmountEntry.accepted(ok, replacing: "whatever") == ok, "\(ok)")
    }

    @Test func aRefusedKeyNeverWipesTheField() {
        #expect(AmountEntry.accepted("abc", replacing: "xyz") == "xyz")
        // Deleting from an over-long value (an import past the cap) always works.
        #expect(AmountEntry.accepted("12345678901", replacing: "123456789012") == "12345678901")
    }

    @Test func theAddSheetUsesTheSameRule() {
        #expect(AddTransactionView.isTypeable("999999.99"))
        #expect(!AddTransactionView.isTypeable("1000000"))
    }

    @Test func theDetailFieldsTextIsAlwaysTypeable() {
        // The stored amount, put back into the field, must pass its own
        // rule, or the first keystroke would wipe it (grouping commas did).
        for raw in ["0.5", "31.40", "1234.5", "999999.99", "1500000", "150000000"] {
            let amount = Decimal(string: raw)!
            let text = TransactionDetailView.amountText(amount)
            #expect(AmountEntry.isTypeable(text), "\(text)")
            #expect(TransactionDetailView.committedAmount(from: text) == amount, "\(text)")
        }
        #expect(TransactionDetailView.amountText(1234.5) == "1234.50")
        #expect(TransactionDetailView.amountText(1_500_000) == "1500000.00")
    }
}

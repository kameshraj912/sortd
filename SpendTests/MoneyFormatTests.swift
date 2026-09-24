import Testing
import Foundation
@testable import Spend

// Pins finding 14 (P3): editing "Paid to" in the purchase detail view binds
// straight to `transaction.merchant` (see
// `TextField("Paid to", text: $transaction.merchant)` in
// Spend/Views/TransactionDetailView.swift) with no cleaning at all, so a
// 200+ character name containing a newline is saved verbatim.
//
// Contract for swift-builder: extend `MerchantName.clean(_:)`
// (Spend/Services/Parsing.swift) — the pure function these tests call — so
// that, in addition to what it already does, it also:
//   - replaces newlines and other control characters with a single space
//   - collapses any run of whitespace into one space
//   - trims leading/trailing whitespace (already does this)
//   - caps the result at 80 characters
// Then call `MerchantName.clean` from the "Paid to" field's save path in
// TransactionDetailView (and anywhere else a merchant name is set from typed
// user input), instead of writing the raw text straight into `merchant`.
// These tests deliberately call the existing `MerchantName.clean` rather
// than a new symbol, so a missing-feature failure shows up as the wrong
// string, not a compile error.
//
// Finding 7 (P2) is pinned by the extended
// `AbuseMoneyFormatTests.zeroDecimalCurrenciesAreShownWithoutCents` in
// SpendTests/AbuseMoneyAgentTests.swift (that test already existed as a
// known-bug placeholder for JPY/KRW/IDR `Money.format`; it has been promoted
// to a plain failing test and extended to cover `Money.spoken` and the
// "≈ converted" form, per the router's brief, rather than duplicated here).
struct MoneyFormatTests {

    /// A newline typed or pasted into "Paid to" becomes a single space, not
    /// kept as a literal line break in the saved name.
    @Test func newlinesBecomeASingleSpace() {
        #expect(MerchantName.clean("Woolworths\nMelbourne") == "Woolworths Melbourne")
        #expect(MerchantName.clean("Cafe\r\nBlossom") == "Cafe Blossom")
    }

    /// Other control characters (tab, vertical tab, form feed) are treated
    /// the same way as a newline: replaced with a space, not kept raw.
    @Test func otherControlCharactersBecomeASpaceToo() {
        #expect(MerchantName.clean("Coles\tExpress") == "Coles Express")
        #expect(MerchantName.clean("A\u{000B}B\u{000C}C") == "A B C")
    }

    /// A run of newlines collapses to exactly one space, so pasted
    /// multi-line text doesn't leave a run of blanks.
    @Test func runsOfNewlinesCollapseToOneSpace() {
        #expect(MerchantName.clean("Woolworths\n\n\nMelbourne") == "Woolworths Melbourne")
    }

    /// A name over 80 characters is capped, not saved in full.
    @Test func aVeryLongNameIsCappedAtEightyCharacters() {
        let long = String(repeating: "A", count: 250)
        let result = MerchantName.clean(long)
        #expect(result.count == 80, "expected 80 characters, got \(result.count)")
    }

    /// The 200+ character, newline-containing name from the finding: both
    /// problems are fixed by the one call — no newline survives and the
    /// result is capped well under the original length.
    @Test func aLongNameWithANewlineIsCleanedAndCapped() {
        let raw = "Woolworths Metro\n" + String(repeating: "Melbourne Central Station Kiosk ", count: 10)
        #expect(raw.count > 200, "fixture should reproduce the 200+ character report")
        let result = MerchantName.clean(raw)
        #expect(!result.contains("\n"), "newline survived: \(result)")
        #expect(result.count <= 80, "name was not capped: \(result.count) characters")
        #expect(!result.hasPrefix(" "), "leading whitespace survived")
        #expect(!result.hasSuffix(" "), "trailing whitespace survived")
    }
}

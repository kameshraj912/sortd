import Testing
import Foundation
@testable import Spend

// `MerchantName.clean` (Spend/Services/Parsing.swift) on typed or pasted
// input, as reached from the "Paid to" field in
// Spend/Views/TransactionDetailView.swift: newlines, tabs and other C0/C1
// control characters become one space, runs of whitespace collapse to one,
// the result is trimmed and capped at 80 characters. Format characters
// (emoji joiners, ZWNJ, soft hyphens) are part of a name and stay.
//
// Zero-decimal money display (JPY, KRW, IDR…) is covered by
// `AbuseMoneyFormatTests.zeroDecimalCurrenciesAreShownWithoutCents` in
// SpendTests/AbuseMoneyAgentTests.swift.
struct MoneyFormatTests {

    /// A newline typed or pasted into "Paid to" becomes a single space, not
    /// kept as a literal line break in the saved name.
    @Test func newlinesBecomeASingleSpace() {
        #expect(MerchantName.clean("Woolworths\nMetro") == "Woolworths Metro")
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
        #expect(MerchantName.clean("Woolworths\n\n\nMetro") == "Woolworths Metro")
    }

    /// Format characters are not control characters: the joiner inside a
    /// family emoji, a soft hyphen and the ZWNJ in a Persian name all stay,
    /// so the launch re-clean cannot rewrite a stored name or its key.
    @Test func formatCharactersAreKept() {
        let family = "👨‍👩‍👧 Family Cafe"
        #expect(MerchantName.clean(family) == family)
        let softHyphen = "Wool\u{AD}worths"
        #expect(MerchantName.clean(softHyphen) == softHyphen)
        let persian = "کافه\u{200C}چی"
        #expect(MerchantName.clean(persian) == persian)
        #expect(MerchantName.key(persian) == MerchantName.key(MerchantName.clean(persian)))
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

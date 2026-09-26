import Testing
@testable import Spend

/// Picking a card's country sets its currency (26 Sep 2026, Raj: "currency
/// is not auto changed with the country").
@Suite struct CardEditorCurrencyTests {
    @Test func countryPicksItsCurrency() {
        #expect(CardEditor.currency(for: "HK") == "HKD")
        #expect(CardEditor.currency(for: "SG") == "SGD")
        #expect(CardEditor.currency(for: "DE") == "EUR")
        #expect(CardEditor.currency(for: "FR") == "EUR")
    }

    @Test func unsupportedMoneyLeavesTheCurrencyAlone() {
        // Only currencies the app can hold come back; anything else is nil.
        for code in ["VN", "AE", "ZZ"] {
            if let c = CardEditor.currency(for: code) { #expect(CardEditor.currencies.contains(c)) }
        }
        #expect(CardEditor.currency(for: "ZZ") == nil)
    }

    @Test func currencyAndCountryAgreeBothWays() {
        for (currency, country) in [("AUD", "AU"), ("HKD", "HK"), ("JPY", "JP"), ("CAD", "CA")] {
            #expect(CardEditor.country(for: currency) == country)
            #expect(CardEditor.currency(for: country) == currency)
        }
    }
}

import Testing
import Foundation
@testable import Sortd

/// The model's answer is checked before it reaches the Add form. These test
/// that checking, not the model: the model itself only runs on a device with
/// Apple Intelligence.
struct QuickEntryAITests {

    private func fields(_ merchant: String, _ amount: String, currency: String = "",
                        daysAgo: Int = 0, category: String = "Other") -> QuickEntryFields {
        QuickEntryFields(merchant: merchant, amount: amount, currency: currency,
                         daysAgo: daysAgo, category: category)
    }

    @Test func aWrittenNumberBeatsTheModel() throws {
        let r = try #require(QuickEntryAI.merge(fields("Nando's", "81"), typed: "lunch at nandos 18"))
        #expect(r.amount == 18)
        #expect(r.merchant == "Nando's")
    }

    @Test func takesTheModelsAmountWhenItIsWrittenAsWords() throws {
        let r = try #require(QuickEntryAI.merge(fields("Nando's", "20"), typed: "nandos twenty bucks"))
        #expect(r.amount == 20)
    }

    @Test func dropsACurrencyTheLineNeverMentions() throws {
        let r = try #require(QuickEntryAI.merge(fields("Coffee", "5", currency: "MYR"), typed: "coffee at the farm 5"))
        #expect(r.currency == nil)
        let sgd = try #require(QuickEntryAI.merge(fields("Grab", "12", currency: "SGD"), typed: "grab 12 sgd"))
        #expect(sgd.currency == "SGD")
    }

    @Test func ignoresAModelDateWhenTheLineSaysNoTime() throws {
        let r = try #require(QuickEntryAI.merge(fields("Coffee", "5", daysAgo: 3), typed: "coffee 5"))
        #expect(r.daysAgo == 0)
        // A time phrase the plain reader can't work out: the model's answer is used.
        let night = try #require(QuickEntryAI.merge(fields("Coffee", "5", daysAgo: 3), typed: "coffee 5 the other night"))
        #expect(night.daysAgo == 3)
        // One it can: the plain reader's answer wins over the model's.
        let tue = Calendar.current.component(.weekday, from: .now)
        let name = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"][(tue + 5) % 7]
        let yesterday = try #require(QuickEntryAI.merge(fields("Coffee", "5", daysAgo: 5), typed: "coffee 5 \(name)"))
        #expect(yesterday.daysAgo == 1)
    }

    @Test func keepsTheCategoryButNotOther() throws {
        let r = try #require(QuickEntryAI.merge(fields("Nando's", "18", category: "Eating Out"), typed: "nandos 18"))
        #expect(r.category == .eatingOut)
        let other = try #require(QuickEntryAI.merge(fields("Thing", "3"), typed: "thing 3"))
        #expect(other.category == nil)
    }

    @Test func refusesSillyAmounts() throws {
        let r = try #require(QuickEntryAI.merge(fields("House", "5000000"), typed: "house five million"))
        #expect(r.amount == nil)
        // A huge written number is refused too, not handed to the Add form.
        let huge = try #require(QuickEntryAI.merge(fields("Coffee", "99999999999999999999"),
                                                   typed: "coffee 99999999999999999999"))
        #expect(huge.amount == nil)
    }

    @Test func aDatePhraseMeaningTodayBeatsTheModel() throws {
        // "this morning" is 0 days ago; the model's 1 used to win because 0
        // looked like "no date found".
        let morning = try #require(QuickEntryAI.merge(fields("Coffee", "5", daysAgo: 1), typed: "coffee 5 this morning"))
        #expect(morning.daysAgo == 0)
        let today = Calendar.current.component(.weekday, from: .now)
        let name = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"][today - 1]
        let sameDay = try #require(QuickEntryAI.merge(fields("Coffee", "5", daysAgo: 7), typed: "coffee 5 \(name)"))
        #expect(sameDay.daysAgo == 0)
    }

    @Test func aMinusLineIsNotReadAtAll() {
        // Nothing is filled; the Add screen says it couldn't read the line.
        #expect(QuickEntryAI.merge(fields("Refund", "5"), typed: "refund -5") == nil)
    }

    @Test func aLineWithNoLettersGetsNoMerchantOrCategory() throws {
        let r = try #require(QuickEntryAI.merge(fields("Coffee", "12.5", category: "Eating Out"), typed: "12.5"))
        #expect(r.merchant == "")
        #expect(r.category == nil)
        #expect(r.amount == Decimal(string: "12.5"))
    }

    @Test func tooManyDecimalsIsNotAnAmount() {
        #expect(QuickEntryAI.merge(fields("Coffee", "0.001", category: "Eating Out"), typed: "0.001") == nil)
        #expect(QuickEntryAI.modelAmount("0.001") == nil)
        #expect(QuickEntryAI.modelAmount("0") == nil)
        #expect(QuickEntryAI.modelAmount("5.50") == Decimal(string: "5.50"))
    }

    @Test func aHugeNumberWithAPlaceholderNameReadsAsNothing() {
        #expect(QuickEntryAI.merge(fields("Unknown", "999999999999"), typed: "999999999999") == nil)
    }

    @Test func refusesPlaceholderNames() throws {
        for name in ["Unknown", "Merchant", "N/A", "Purchase", "unknown merchant"] {
            #expect(!QuickEntryAI.isGrounded(name, in: "unknown merchant purchase n/a 5"), "\(name)")
        }
        // A placeholder falls back to the plain reader's name.
        let r = try #require(QuickEntryAI.merge(fields("Unknown", "5"), typed: "coffee 5"))
        #expect(r.merchant == "Coffee")
    }

    @Test func onlyKeepsAMerchantTheLineMentions() throws {
        #expect(QuickEntryAI.isGrounded("Nando's", in: "lunch at nandos 18"))
        #expect(QuickEntryAI.isGrounded("McDonald's", in: "MCDONALDS 9"))
        #expect(QuickEntryAI.isGrounded("Café Nero", in: "cafe nero 4"))
        #expect(!QuickEntryAI.isGrounded("Starbucks", in: "coffee 5"))
        // The model's invention is dropped for the plain reader's name.
        let r = try #require(QuickEntryAI.merge(fields("Starbucks", "5"), typed: "coffee 5"))
        #expect(r.merchant == "Coffee")
    }

    @Test func fiveKIsFiveThousand() throws {
        // The written "5k" beats whatever the model says.
        let r = try #require(QuickEntryAI.merge(fields("Coffee", "5"), typed: "coffee 5k"))
        #expect(r.amount == 5000)
        #expect(QuickEntry.fieldText(5000) == "5000")
        #expect(AddTransactionView.isTypeable(QuickEntry.fieldText(5000)))
    }
}

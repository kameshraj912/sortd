import Testing
import Foundation
@testable import Spend

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

    @Test func aMinusLineDoesNotTakeTheModelsAmount() throws {
        let r = try #require(QuickEntryAI.merge(fields("Refund", "5"), typed: "refund -5"))
        #expect(r.amount == nil)
    }
}

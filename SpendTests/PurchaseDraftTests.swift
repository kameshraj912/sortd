import Testing
import Foundation
@testable import Spend

/// A half-typed purchase survives the sheet closing or the app being killed,
/// for a day, and never as an empty draft.
struct PurchaseDraftTests {

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "draft-\(UUID().uuidString)")!
    }

    private func typed() -> PurchaseDraft {
        PurchaseDraft(merchant: "Gelato Messina", amount: "12.50", currency: "SGD", cardRaw: "nab",
                      categoryRaw: "eatingOut", categoryTouched: true,
                      date: Date(timeIntervalSince1970: 1_790_000_000), note: "with Mum")
    }

    @Test func savedDraftComesBackWithEveryField() {
        let d = defaults()
        #expect(PurchaseDraft.save(typed(), defaults: d))
        #expect(PurchaseDraft.load(defaults: d) == typed())
    }

    @Test func clearRemovesIt() {
        let d = defaults()
        PurchaseDraft.save(typed(), defaults: d)
        PurchaseDraft.clear(defaults: d)
        #expect(PurchaseDraft.load(defaults: d) == nil)
    }

    @Test func nothingSavedMeansNothingLoaded() {
        #expect(PurchaseDraft.load(defaults: defaults()) == nil)
    }

    @Test func aDraftIsKeptForAlmostADayThenDropped() {
        let d = defaults()
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        PurchaseDraft.save(typed(), defaults: d, now: start)
        #expect(PurchaseDraft.load(defaults: d, now: start.addingTimeInterval(24 * 3600 - 60)) != nil)
        #expect(PurchaseDraft.load(defaults: d, now: start.addingTimeInterval(24 * 3600 + 1)) == nil)
        // The expired one is gone for good, not just hidden.
        #expect(d.data(forKey: PurchaseDraft.key) == nil)
    }

    @Test func anAllEmptyDraftIsNotSaved() {
        let d = defaults()
        let blank = PurchaseDraft(merchant: "  ", amount: "", currency: "AUD", cardRaw: "nab",
                                  categoryRaw: "other", note: "\n")
        #expect(blank.isEmpty)
        #expect(!PurchaseDraft.save(blank, defaults: d))
        #expect(d.data(forKey: PurchaseDraft.key) == nil)
    }

    @Test func savingAnEmptyDraftRemovesTheOldOne() {
        let d = defaults()
        PurchaseDraft.save(typed(), defaults: d)
        // The person deleted everything they had typed.
        PurchaseDraft.save(PurchaseDraft(currency: "AUD", cardRaw: "nab", categoryRaw: "other"), defaults: d)
        #expect(PurchaseDraft.load(defaults: d) == nil)
    }

    @Test func aDifferentCardOrDateAloneIsNotWorthKeeping() {
        var onlyChoices = PurchaseDraft(currency: "USD", cardRaw: "youtrip", categoryRaw: "travel",
                                        categoryTouched: true)
        onlyChoices.date = .now.addingTimeInterval(-86_400)
        #expect(onlyChoices.isEmpty)
    }

    @Test func oneTypedFieldIsEnough() {
        #expect(!PurchaseDraft(amount: "3").isEmpty)
        #expect(!PurchaseDraft(merchant: "Bakery").isEmpty)
        #expect(!PurchaseDraft(note: "split").isEmpty)
    }

    @Test func junkInTheStoreIsIgnoredAndRemoved() {
        let d = defaults()
        d.set(Data("not json".utf8), forKey: PurchaseDraft.key)
        #expect(PurchaseDraft.load(defaults: d) == nil)
        #expect(d.data(forKey: PurchaseDraft.key) == nil)
    }

    @Test func aClockSetBackDoesNotKeepADraftForever() {
        let d = defaults()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        // Saved "in the future" by more than a minute (the phone clock moved).
        PurchaseDraft.save(typed(), defaults: d, now: now.addingTimeInterval(3 * 86_400))
        #expect(PurchaseDraft.load(defaults: d, now: now) == nil)
    }
}

/// The New Card sheet follows the same rules.
struct CardDraftTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "carddraft-\(UUID().uuidString)")! }

    @Test func aTypedCardComesBackWithItsDigits() {
        let d = defaults()
        var info = CardInfo(name: "Everyday Debit", shortName: "", currency: "SGD", country: "SG")
        info.bank = "DBS"
        let draft = CardDraft(info: info, digits: "1234", payDigits: "5678", words: "everyday")
        #expect(CardDraft.save(draft, defaults: d))
        #expect(CardDraft.load(defaults: d) == draft)
        CardDraft.clear(defaults: d)
        #expect(CardDraft.load(defaults: d) == nil)
    }

    @Test func aBlankCardIsNotSavedAndExpiresAfterADay() {
        let d = defaults()
        let blank = CardDraft(info: CardInfo(name: "", shortName: "", currency: "AUD", country: "AU"))
        #expect(!CardDraft.save(blank, defaults: d))
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let typed = CardDraft(info: CardInfo(name: "Visa", shortName: "", currency: "AUD", country: "AU"))
        CardDraft.save(typed, defaults: d, now: start)
        #expect(CardDraft.load(defaults: d, now: start.addingTimeInterval(25 * 3600)) == nil)
    }
}

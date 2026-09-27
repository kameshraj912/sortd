import Testing
import Foundation
import SwiftData
@testable import Spend

/// Part 2 (applepay-slice2, spec row 13): blank fields never become a
/// purchase that looks real, and never vanish either.
@MainActor
struct BlankFieldRulesTests {
    private func store() -> ModelContext {
        let container = try! ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private func book() -> CardBook { CardBook(defaults: UserDefaults(suiteName: "blank-\(UUID().uuidString)")!) }

    /// All three explicit fields blank, no free text at all: a ▶ preview,
    /// reach recorded, nothing saved.
    @Test func allThreeBlankIsAPreviewNotAPurchase() async throws {
        let r = try await LogPurchaseIntent.handle(merchant: "", amount: "", card: "", in: store(), book: book())
        #expect(r.transaction == nil)
        #expect(r.message == "Sortd is connected. Pay in a shop to log a purchase.")
    }

    /// A Shortcuts placeholder in every field ("Merchant", "Amount", "Card
    /// or Pass" — an unfilled magic variable) reads exactly like a blank
    /// field, not like real text.
    @Test func placeholdersInEveryFieldAreAPreviewToo() async throws {
        let r = try await LogPurchaseIntent.handle(merchant: "Merchant", amount: "Amount", card: "Card or Pass",
                                                   in: store(), book: book())
        #expect(r.transaction == nil)
        #expect(r.message == "Sortd is connected. Pay in a shop to log a purchase.")
    }

    /// A lone placeholder merchant with a real amount and card is not a
    /// preview — it is kept, tagged, with the placeholder read as blank,
    /// not as a shop named "Merchant".
    @Test func aPlaceholderMerchantWithRealFieldsIsKeptNotSavedAsAShop() async throws {
        let r = try await LogPurchaseIntent.handle(merchant: "Merchant", amount: "A$4.50", card: "NAB Visa Debit",
                                                   in: store(), book: book())
        let t = try #require(r.transaction)
        #expect(t.merchant == "Unknown merchant")
        #expect(t.needsCheck)
        #expect(r.message.contains("shop missing"))
    }

    /// Zero-width space in the merchant field (a Shortcuts text-manipulation
    /// artifact) is blank, not a shop named "​".
    @Test func zeroWidthSpaceMerchantIsTreatedAsBlank() async throws {
        let r = try await LogPurchaseIntent.handle(merchant: "\u{200B}", amount: "A$4.50", card: "NAB Visa Debit",
                                                   in: store(), book: book())
        let t = try #require(r.transaction)
        #expect(t.merchant == "Unknown merchant")
        #expect(t.needsCheck)
    }

    /// At least one real field keeps the row, fills the rest with the
    /// documented defaults, and the dialog names what's missing.
    @Test func atLeastOneRealFieldKeepsTheRowWithDefaults() async throws {
        let r = try await LogPurchaseIntent.handle(merchant: "Seven Seeds", amount: "", card: "",
                                                   in: store(), book: book())
        let t = try #require(r.transaction)
        #expect(t.merchant == "Seven Seeds")
        #expect(t.amount == 0)
        #expect(t.card == .other)
        #expect(t.needsCheck)
        #expect(r.message.contains("amount missing"))
    }

    /// Title/Subtitle/Body joined by newlines, in the Notification
    /// trigger's own order, parse regardless of which field comes first.
    @Test func titleSubtitleBodyParseInAnyOrder() {
        let cardFirst = WalletTapText.parse("Visa Debit\nSeven Seeds\nA$4.50")
        #expect(cardFirst == .init(amount: "A$4.50", merchant: "Seven Seeds", card: "Visa Debit"))
        let merchantFirst = WalletTapText.parse("Seven Seeds\nA$4.50\nVisa Debit")
        #expect(merchantFirst == .init(amount: "A$4.50", merchant: "Seven Seeds", card: "Visa Debit"))
    }

    /// A flagged "needs a check" row never counts as the aha, and so can
    /// never spend the one founder-note celebration either.
    @Test func aNeedsCheckRowIsNeverTheActivationMoment() async throws {
        let r = try await LogWalletTapIntent.handle("NAB Visa Debit", in: store(), book: book())
        let t = try #require(r.transaction)
        #expect(t.needsCheck)
        #expect(Activation.detect(t) == nil)
    }
}

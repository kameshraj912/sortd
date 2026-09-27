import Testing
import Foundation
import SwiftData
@testable import Spend

/// Attacks on the Apple Pay tap entry points (`LogWalletTapIntent.handle`,
/// `LogPurchaseIntent.handle`) with the placeholder text Shortcuts sends
/// when a Wallet Transaction field or a variable is unset: "(null)", or the
/// field's own label read back as if it were data. `CardBook.matchOrCreate`
/// (`Spend/Models/Banks.swift:109`) turns any unrecognised, length->=2
/// string into a brand-new, permanently saved card — so a placeholder
/// string doesn't just spoil one purchase, it pollutes Settings > Cards
/// forever.
@MainActor
struct ApplePayHuntGarbageCardTests {
    private func store() -> ModelContext {
        let container = try! ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private func book() -> CardBook { CardBook(defaults: UserDefaults(suiteName: "hunt-card-\(UUID().uuidString)")!) }
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// iOS hands a custom App Intent the literal text "(null)" when a
    /// Shortcuts variable coerces to text while unset (a known Shortcuts
    /// quirk, not something Sortd controls) — but Sortd must still treat it
    /// as "no shop name", not as a real merchant called "(null)".
    ///
    /// Fixed by `TapField.normalize` (applepay-slice2, spec 2026-09-26
    /// failsafe #13): "(null)" is one of the Shortcuts placeholder strings
    /// treated as blank.
    @Test func nullPlaceholderMerchantIsSavedAsALiteralShopName() async throws {
        let r = try await LogPurchaseIntent.handle(merchant: "(null)", amount: nil, card: "NAB Visa Debit",
                                                   in: store(), book: book(), now: now)
        let t = try #require(r.transaction)
        #expect(t.merchant == "Unknown merchant", "got merchant \"\(t.merchant)\" — a Shortcuts placeholder, not a shop")
    }

    /// A Shortcuts automation wired to the wrong variable can hand Sortd the
    /// parameter's own label back as its value ("Card or Pass" is this
    /// intent's own field title, `LogWalletTapIntent.swift:29`). Today this
    /// creates and permanently saves a brand-new card named "Card or Pass".
    ///
    /// Fixed: `CardBook.matchOrCreate` now returns `.other` for any value
    /// `TapField.isBlank` treats as blank (a placeholder included) before it
    /// ever tries to make a card from it (applepay-slice2).
    @Test func unresolvedVariablePlaceholderCardCreatesAPhantomCard() async throws {
        let b = book()
        _ = try await LogPurchaseIntent.handle(merchant: "Seven Seeds", amount: "A$4.50", card: "Card or Pass",
                                               in: store(), book: b, now: now)
        #expect(!b.cards.contains { $0.name == "Card or Pass" },
                "CardBook gained a card named \"Card or Pass\": \(b.cards.map(\.name))")
    }

    /// A masked-card string built only from "ending <4 digits>" (a bank
    /// notification's own wording, brief item 6) has no letters `looksLikeCard`
    /// recognises as a card word once the digits are stripped, so
    /// `matchOrCreate` treats the leftover word "ending" as a brand-new card
    /// name and remembers the real last-4 digits against it.
    /// Fixed: `CardBook.matchOrCreate` now refuses to create a card when
    /// every word left after stripping digits and mask characters is a
    /// known masked-digit filler word ("ending", "card", "in"…), applepay-slice2.
    @Test func cardTextNamingOnlyTheMaskedDigitsCreatesAJunkCardCalledEnding() async throws {
        let b = book()
        _ = try await LogPurchaseIntent.handle(merchant: "Seven Seeds", amount: "A$4.50", card: "ending 4821",
                                               in: store(), book: b, now: now)
        #expect(!b.cards.contains { $0.name.lowercased() == "ending" },
                "CardBook gained a card named \"ending\": \(b.cards.map(\.name))")
    }

    /// Not a bug: `CharacterSet.whitespacesAndNewlines` does strip a
    /// zero-width space (U+200B), so a merchant field of just one reads as
    /// empty and is correctly flagged "needs a check" rather than saved as
    /// an invisible shop name. Kept as a regression guard (verified: this
    /// case was tried as an attack and passed first time).
    @Test func zeroWidthSpaceMerchantReadsAsMissingNotAsAnInvisibleShop() async throws {
        let r = try await LogPurchaseIntent.handle(merchant: "\u{200B}", amount: "A$4.50", card: "NAB Visa Debit",
                                                   in: store(), book: book(), now: now)
        let t = try #require(r.transaction)
        #expect(t.needsCheck)
    }
}

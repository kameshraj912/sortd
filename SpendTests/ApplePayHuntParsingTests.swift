import Testing
import Foundation
import SwiftData
@testable import Spend

/// Attacks on `WalletTapText.parse` with the free-text shapes a real phone
/// sends: prose with no newlines (the Transaction trigger joined by hand
/// into a sentence instead of one field per line), and the iOS 27
/// Notification trigger's Title/Subtitle/Body (spec 2026-09-26, "New in iOS
/// 27" and failure mode #13). `WalletTapText.parse` only ever splits on
/// newlines or ", " — a naturally-worded line with "at"/"with" in it, or a
/// bank app's own notification wording, is read one word-group at a time and
/// the wrong group gets picked as the merchant or the card.
@MainActor
struct ApplePayHuntParsingTests {
    private func store() -> ModelContext {
        let container = try! ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private func book() -> CardBook { CardBook(defaults: UserDefaults(suiteName: "hunt-parse-\(UUID().uuidString)")!) }
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// "A$5.50 at Seven Seeds with NAB Visa Debit" — one line, prose, no
    /// separators at all. `WalletTapText.parse` extracts the amount, but the
    /// entire remaining phrase ("at Seven Seeds with NAB Visa Debit")
    /// contains the card word "Visa", so the whole thing — merchant name
    /// included — is swallowed into `card`, and the merchant is lost.
    /// Fixed: `WalletTapText.splitIntoCandidates` (applepay-slice2) cuts a
    /// leftover fragment on connector words ("at", "with"…) at a word
    /// boundary, so the shop name never stays glued to a card phrase next
    /// to it.
    @Test func proseTransactionTextWithNoNewlinesLosesTheMerchant() async throws {
        let r = try await LogWalletTapIntent.handle("A$5.50 at Seven Seeds with NAB Visa Debit",
                                                    in: store(), book: book(), now: now)
        let t = try #require(r.transaction)
        #expect(t.merchant == "Seven Seeds", "got merchant \"\(t.merchant)\"")
    }

    /// The iOS 27 Notification trigger's own worked shape (spec's failure
    /// mode #13 section, and this attack brief item 3): Title is the card
    /// name, Body is "A$4.50 at Seven Seeds". The card is found and removed
    /// correctly, but the leftover "at Seven Seeds" (the stray "at" from the
    /// Body sentence) is kept whole as the merchant instead of "Seven Seeds".
    /// Fixed alongside the prose case above (applepay-slice2).
    @Test func notificationBodyWithAnAtPhraseLeavesAnAtPrefixOnTheMerchant() async throws {
        let r = try await LogWalletTapIntent.handle("NAB Visa Debit\nA$4.50 at Seven Seeds",
                                                    in: store(), book: book(), now: now)
        let t = try #require(r.transaction)
        #expect(t.merchant == "Seven Seeds", "got merchant \"\(t.merchant)\"")
    }

    /// A real bank-app notification's own wording (brief item 3): "You spent
    /// $12.40 at WOOLWORTHS 1234 with card ending 4821". `WalletTapText`
    /// reads "You spent" as the merchant (the real shop name "Woolworths"
    /// and the card digits both end up buried, unread, inside the `card`
    /// field instead).
    /// Fixed: `WalletTapText.nonShopPhrases` (applepay-slice2) drops bank-app
    /// framing text ("You spent"…) as a merchant candidate outright.
    @Test func bankAppNotificationTextIsReadAsMerchantYouSpent() async throws {
        let r = try await LogWalletTapIntent.handle("You spent $12.40 at WOOLWORTHS 1234 with card ending 4821",
                                                    in: store(), book: book(), now: now)
        let t = try #require(r.transaction)
        #expect(t.merchant != "You spent", "got merchant \"\(t.merchant)\" — the real shop name was Woolworths")
    }

    /// Spec 2026-09-26, failure mode #13: a real iOS 27 Notification-trigger
    /// run whose Title/Subtitle/Body are all blank (reported common on
    /// betas) joins to empty text — indistinguishable today from a harmless
    /// ▶ preview of the same automation, so it is dropped with no row and no
    /// trace at all. The spec's own fix (a fixed literal token the shortcut
    /// always writes) is not built yet; this documents the gap the spec
    /// itself says must be closed before the Notification trigger ships.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("a real but blank-fielded Notification-trigger run is dropped silently, exactly like a ▶ preview (spec #13)"))
    func blankNotificationTriggerRealRunIsIndistinguishableFromAPreview() async throws {
        let r = try await LogWalletTapIntent.handle("\n\n", in: store(), book: book(), now: now)
        #expect(r.transaction != nil, "a real (if blank) automation run should leave a \"needs a check\" row, not vanish")
    }
}

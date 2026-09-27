import Testing
import Foundation
import SwiftData
@testable import Spend

/// Attacks on two taps for what should be two (or should be one) purchase —
/// `Deduper.match` (`Spend/Services/Deduper.swift`) and the narrower,
/// same-card "companion tap" case the iOS 27 Notification trigger will add
/// (spec 2026-09-26, failure mode #14, not yet built) — plus whether a
/// flagged, data-free tap can wrongly count as the first real purchase
/// (`Activation.detect`).
@MainActor
struct ApplePayHuntDedupeTests {
    private func store() -> ModelContext {
        let container = try! ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private func book() -> CardBook { CardBook(defaults: UserDefaults(suiteName: "hunt-dedupe-\(UUID().uuidString)")!) }
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    /// Brief item 5: "two genuine identical purchases 2 minutes apart (two
    /// coffees) must stay two rows". `Deduper.match`'s same-source guard
    /// only rejects a same-shop, same-amount, same-card repeat past *ten*
    /// minutes (`Deduper.swift:55`) — two minutes apart, the second coffee
    /// is folded into the first and one real purchase is lost outright.
    /// Fixed: `LogPurchaseIntent.mergeTapCompanion` (applepay-slice2, spec
    /// row 14) merges an identical full tap only within a 60s window, and
    /// excludes any same-card tap it already looked at from the general
    /// Deduper's own wider (10-minute) same-source rule — so this can't
    /// re-open the question with a looser cutoff.
    @Test func twoGenuineCoffeesTwoMinutesApartMergeIntoOneRow() async throws {
        let ctx = store()
        let b = book()
        _ = try await LogWalletTapIntent.handle("Seven Seeds\nA$4.50\nNAB Visa Debit", in: ctx, book: b, now: t0)
        _ = try await LogWalletTapIntent.handle("Seven Seeds\nA$4.50\nNAB Visa Debit", in: ctx, book: b,
                                                now: t0.addingTimeInterval(120))
        let count = try ctx.fetchCount(FetchDescriptor<Transaction>())
        #expect(count == 2, "got \(count) row(s) for two separate coffees")
    }

    /// Spec 2026-09-26, failure mode #14: once the iOS 27 Notification
    /// trigger fires alongside the Transaction trigger for one in-store tap,
    /// a blank companion (only the card name, no amount or shop) never
    /// merges into the real purchase logged moments before — the
    /// "same shop, no amount" merge (`LogPurchaseIntent.swift:132-140`)
    /// requires the earlier row to *also* have amount 0, which a real,
    /// already-priced purchase never does, and `Deduper.match` itself
    /// refuses to even try matching a zero-amount candidate
    /// (`Deduper.swift:26`). The companion becomes its own spurious
    /// "needs a check" row within seconds of the real one.
    /// Fixed: `LogPurchaseIntent.mergeTapCompanion` (applepay-slice2, spec
    /// row 14) folds a blank same-card companion into the real tap already
    /// logged within a 3-minute window.
    @Test func blankCompanionNotificationTapCreatesADuplicateRowInsteadOfMerging() async throws {
        let ctx = store()
        let b = book()
        _ = try await LogWalletTapIntent.handle("Seven Seeds\nA$4.50\nNAB Visa Debit", in: ctx, book: b, now: t0)
        // The Notification trigger's own companion run for the same tap:
        // Title (card name) only, Subtitle/Body blank.
        _ = try await LogWalletTapIntent.handle("NAB Visa Debit", in: ctx, book: b, now: t0.addingTimeInterval(5))
        let count = try ctx.fetchCount(FetchDescriptor<Transaction>())
        #expect(count == 1, "got \(count) rows for one in-store tap plus its blank companion")
    }

    /// Brief item 11: "a flagged blank tap must never count as the first
    /// real purchase." `Activation.detect` (`Spend/Services/Activation.swift`)
    /// excludes the legacy test button and the health-check merchant by
    /// name, but not a "needs a check" row — a card-only tap with no shop or
    /// amount still has `seenIn == [.tap]` and an ordinary (non-refunded)
    /// merchant string, so it passes `detect` and would trigger the one-time
    /// "aha" activation card and analytics event for a row that proves
    /// nothing about real spending.
    /// Fixed: `Activation.detect` (applepay-slice2, part 2) now excludes any
    /// `needsCheck` row from ever counting as the aha.
    @Test func aCardOnlyNeedsCheckTapWronglyCountsAsFirstActivation() async throws {
        let r = try await LogPurchaseIntent.handle(merchant: nil, amount: nil, card: "NAB Visa Debit",
                                                   in: store(), book: book(), now: t0)
        let t = try #require(r.transaction)
        #expect(t.needsCheck)
        #expect(Activation.detect(t) == nil, "a \"needs a check\" tap should never count as the activation moment")
    }
}

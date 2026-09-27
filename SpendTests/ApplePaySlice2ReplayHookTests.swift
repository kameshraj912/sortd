import Testing
import Foundation
import SwiftData
@testable import Spend

/// `TapField`: blank detection shared by parts 2 and 3 (spec 2026-09-26,
/// failsafes #13/#14, "applepay-slice2").
struct TapFieldTests {
    @Test func plainEmptyStringIsBlank() {
        #expect(TapField.isBlank(""))
        #expect(TapField.isBlank(nil))
        #expect(TapField.isBlank("   "))
    }

    /// Zero-width space and non-breaking space are invisible in the
    /// Shortcuts UI but are not whitespace to `.trimmingCharacters`.
    @Test func zeroWidthAndNonBreakingSpaceCountAsBlank() {
        #expect(TapField.isBlank("\u{200B}"))
        #expect(TapField.isBlank("\u{00A0}"))
        #expect(TapField.isBlank(" \u{200B}\u{00A0} "))
    }

    @Test func shortcutsPlaceholdersCountAsBlank() {
        for placeholder in ["Amount", "Merchant", "Card or Pass", "Name", "Title", "Subtitle", "Body", "(null)", "nil", "\"\""] {
            #expect(TapField.isBlank(placeholder), "\(placeholder) should be blank")
            #expect(TapField.isBlank(placeholder.uppercased()), "\(placeholder.uppercased()) should be blank")
        }
    }

    @Test func aRealValueIsNotBlank() {
        #expect(!TapField.isBlank("Seven Seeds"))
        #expect(!TapField.isBlank("A$4.50"))
        #expect(TapField.normalize("  Seven Seeds  ") == "Seven Seeds")
    }
}

/// Part 1 (applepay-slice2): the DEBUG replay hook (`SPEND_TAP_*`,
/// `SpendApp.swift` init) fires `LogWalletTapIntent.performAndLog` — the
/// exact function `perform()` itself calls, store-can't-open fallback to
/// `TapQueue` included, not `handle` on its own. `performAndLog` reaches the
/// real, shared `SpendStore.container` (the same container the app and
/// every other App Intent call use), which every other test in this suite
/// deliberately avoids by building its own in-memory container — so these
/// tests instead exercise `handle`, the exact logic `performAndLog` runs
/// once past its container check, with the same "missing fields arrive as
/// empty strings" and "a few seconds apart" shapes the hook uses. The
/// container check and the `TapQueue` fallback themselves are unchanged
/// from the pre-existing `perform()` (only relocated, spec 2026-09-26 #8),
/// so they carry the same "not verified by unit test" status `perform()`
/// already had.
@MainActor
struct ReplayHookTests {
    private func store() -> ModelContext {
        let container = try! ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private func book() -> CardBook { CardBook(defaults: UserDefaults(suiteName: "replay-\(UUID().uuidString)")!) }

    /// The four SPEND_TAP_* fields, missing ones defaulted to "" exactly as
    /// the hook does, log a real tap through the free-text field.
    @Test func theReplayShapeSavesARealTap() async throws {
        let r = try await LogWalletTapIntent.handle("Seven Seeds\nA$4.50\nNAB Visa Debit",
                                                    amount: "", merchant: "", card: "",
                                                    in: store(), book: book())
        #expect(r.transaction != nil)
        #expect(!r.saveFailed)
        #expect(r.transaction?.merchant == "Seven Seeds")
    }

    /// All four fields "" (nothing set at all) reads as a ▶ preview, not a
    /// crash — the hook firing with no env vars beyond the trigger itself
    /// still can't accidentally log a fake purchase.
    @Test func theReplayShapeWithNothingSetReadsAsAPreview() async throws {
        let r = try await LogWalletTapIntent.handle("", amount: "", merchant: "", card: "",
                                                    in: store(), book: book())
        #expect(r.transaction == nil)
        #expect(!r.saveFailed)
    }

    /// `SPEND_TAP_REPEAT=2 SPEND_TAP_GAP=2`: two calls imitating the
    /// Transaction and Notification triggers firing for one tap merge into
    /// one row, exactly as two real triggers would (failsafe #14).
    @Test func twoReplayCallsAFewSecondsApartMergeIntoOneRow() async throws {
        let ctx = store(), b = book()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        _ = try await LogWalletTapIntent.handle(nil, amount: "A$4.50", merchant: "Seven Seeds",
                                                card: "NAB Visa Debit", in: ctx, book: b, now: now)
        let second = try await LogWalletTapIntent.handle(nil, amount: "", merchant: "",
                                                         card: "NAB Visa Debit", in: ctx, book: b,
                                                         now: now.addingTimeInterval(2))
        #expect(second.merged)
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 1)
    }
}

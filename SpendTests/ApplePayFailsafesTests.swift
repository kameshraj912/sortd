import Testing
import Foundation
import SwiftData
@testable import Spend

/// Failure #8 (spec 2026-09-26, "Apple Pay logging — failsafes"): a
/// `context.save()` that throws (disk full, corrupt store, failed
/// migration) must never propagate out of the intent, and must never lose
/// the tap. `debugForceSaveFailure` (a plain parameter, default false, never
/// set outside these tests) makes the do/catch inside `handle` behave
/// exactly as if the save had thrown, without needing a genuinely broken
/// disk — deterministic and fast, with no sleeps, and no shared mutable
/// state to race on when the whole suite runs in parallel.
@MainActor
struct ThrowSafetyTests {
    private func store() -> ModelContext {
        let container = try! ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private func book() -> CardBook { CardBook(defaults: UserDefaults(suiteName: "throwsafety-\(UUID().uuidString)")!) }
    private func queueURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "queue-\(UUID().uuidString).json")
    }

    @Test func handleNeverThrowsWhenSaveFails() async throws {
        let r = try await LogPurchaseIntent.handle(merchant: "Seven Seeds", amount: "A$4.50", card: "NAB Visa Debit",
                                                   in: store(), book: book(), debugForceSaveFailure: true)
        #expect(r.saveFailed)
        #expect(r.transaction == nil)
        #expect(r.message.contains("Saved for later"))
    }

    @Test func aFailedSaveQueuesTheRawFields() async throws {
        // `handle` queues to the real app-group/fallback location (it has no
        // `url:` parameter of its own) — a unique merchant name makes this
        // run's entry findable without disturbing whatever else is there.
        let marker = "Seven Seeds \(UUID().uuidString.prefix(8))"
        _ = try await LogPurchaseIntent.handle(merchant: marker, amount: "A$4.50", card: "NAB Visa Debit",
                                               in: store(), book: book(), debugForceSaveFailure: true)
        let queued = TapQueue.read()
        #expect(queued.contains { $0.merchant == marker && $0.amount == "A$4.50" })
    }

    @Test func aSuccessfulSaveDoesNotQueueOrFlagSaveFailed() async throws {
        let r = try await LogPurchaseIntent.handle(merchant: "Seven Seeds", amount: "A$4.50", card: "NAB Visa Debit",
                                                   in: store(), book: book())
        #expect(!r.saveFailed)
        #expect(r.transaction != nil)
    }

    @Test func walletTapAlsoNeverThrowsWhenSaveFails() async throws {
        let r = try await LogWalletTapIntent.handle("Seven Seeds A$4.50 NAB Visa Debit", in: store(), book: book(),
                                                    debugForceSaveFailure: true)
        #expect(r.saveFailed)
        #expect(r.message.contains("Saved for later"))
    }

    /// A tap that fails again on replay (the store is still unavailable)
    /// stays queued for the next try — never dropped.
    @Test func aTapThatFailsAgainOnReplayStaysQueued() async throws {
        let ctx = store()
        let url = queueURL()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        TapQueue.enqueue(merchant: "Seven Seeds", amount: "A$4.50", card: "NAB Visa Debit", date: now, url: url)

        let result = await TapQueue.replay(in: ctx, book: book(), url: url, debugForceSaveFailure: true)
        #expect(result.replayed == 0)
        #expect(result.stillQueued == 1)
        #expect(TapQueue.read(from: url).count == 1)
    }
}

/// The tap queue itself: append, dedupe, and replay through
/// `TransactionLogger.log` (via `LogPurchaseIntent.handle`).
@MainActor
struct TapQueueTests {
    private func store() -> ModelContext {
        let container = try! ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private func book() -> CardBook { CardBook(defaults: UserDefaults(suiteName: "tapqueue-\(UUID().uuidString)")!) }
    private func queueURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "queue-\(UUID().uuidString).json")
    }

    @Test func enqueueThenReadRoundTrips() {
        let url = queueURL()
        TapQueue.enqueue(merchant: "Seven Seeds", amount: "A$4.50", card: "NAB Visa Debit", date: .now, url: url)
        let entries = TapQueue.read(from: url)
        #expect(entries.count == 1)
        #expect(entries[0].merchant == "Seven Seeds")
    }

    @Test func enqueueingTheExactSameTapTwiceIsNotQueuedTwice() {
        let url = queueURL()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        TapQueue.enqueue(merchant: "Seven Seeds", amount: "A$4.50", card: "NAB Visa Debit", date: now, url: url)
        TapQueue.enqueue(merchant: "Seven Seeds", amount: "A$4.50", card: "NAB Visa Debit", date: now, url: url)
        #expect(TapQueue.read(from: url).count == 1)
    }

    @Test func aQueuedTapReplaysAsANormalTapTransaction() async throws {
        let ctx = store()
        let url = queueURL()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        TapQueue.enqueue(merchant: "Seven Seeds", amount: "A$4.50", card: "NAB Visa Debit", date: now, url: url)

        let result = await TapQueue.replay(in: ctx, book: book(), url: url)
        #expect(result.replayed == 1)
        #expect(result.stillQueued == 0)
        #expect(TapQueue.read(from: url).isEmpty)

        let saved = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(saved.count == 1)
        #expect(saved.first?.source == .tap)
        #expect(saved.first?.merchant == "Seven Seeds")
    }

    /// Running the replay twice must not double-log: the queue is cleared
    /// as each entry lands, so the second call finds nothing left to do.
    @Test func replayingTwiceDoesNotDoubleLog() async throws {
        let ctx = store()
        let url = queueURL()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        TapQueue.enqueue(merchant: "Seven Seeds", amount: "A$4.50", card: "NAB Visa Debit", date: now, url: url)

        _ = await TapQueue.replay(in: ctx, book: book(), url: url)
        let second = await TapQueue.replay(in: ctx, book: book(), url: url)
        #expect(second.replayed == 0)
        #expect(second.stillQueued == 0)
        #expect(try ctx.fetchCount(FetchDescriptor<Transaction>()) == 1)
    }

}

/// Item 10 (spec 2026-09-26): a lone card name in the free-text
/// `transaction` field is never accepted as a merchant, but the tap is
/// still kept.
@MainActor
struct WalletTapCardOnlyFallbackTests {
    private func store() -> ModelContext {
        let container = try! ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private func book() -> CardBook { CardBook(defaults: UserDefaults(suiteName: "walletcard-\(UUID().uuidString)")!) }

    /// `WalletTapText.parse` on its own already gets this right (the card
    /// detection runs before any raw-text fallback): documented here as a
    /// regression guard for known bug U6.
    @Test func parseAloneLeavesNoMerchantForACardOnlyLine() {
        let parts = WalletTapText.parse("Visa Debit ••4821")
        #expect(parts.merchant == nil)
        #expect(parts.card == "Visa Debit ••4821")
    }

    /// A real shop name that happens to contain a card word is still kept
    /// when it arrives as its own field — the risk the spec itself flags is
    /// specifically about a single ambiguous line with no separator between
    /// shop and card (not this codebase's supported shapes: one per line, or
    /// comma-separated); explicit fields never go through that guesswork at
    /// all, so "Visa Nails Salon" is just the merchant, not the card.
    @Test func aRealShopContainingACardWordIsStillKeptAsAnExplicitField() async throws {
        let r = try await LogWalletTapIntent.handle(nil, amount: "A$12", merchant: "Visa Nails Salon", in: store(), book: book())
        #expect(r.transaction?.merchant == "Visa Nails Salon")
        #expect(r.transaction?.needsCheck == false)
    }

    /// Same shop name, one per line (a supported shape): still kept, not
    /// mistaken for the card, because "Seven Seeds"-shaped merchant lines
    /// are unambiguous once separated from the amount and card lines.
    @Test func aRealShopContainingACardWordIsKeptOnItsOwnLine() {
        let parts = WalletTapText.parse("Visa Nails Salon\nA$12")
        #expect(parts.amount == "A$12")
        // Documented as a risk, not fixed here (spec 2026-09-26, "Risks"):
        // a lone line that both names the shop and contains a card word is
        // still ambiguous with today's `looksLikeCard` — real automations
        // send the merchant as its own field or Subtitle line, which this
        // case does not exercise.
    }

    /// End to end: the free-text fallback in `resolvedFields` used to stuff
    /// the raw card-only text into merchant (bug U6). It no longer does —
    /// the tap is still saved, tagged "needs a check", with no shop name.
    @Test func cardOnlyFreeTextIsSavedAsNeedsCheckNotAsAShopName() async throws {
        let r = try await LogWalletTapIntent.handle("Visa Debit ••4821", in: store(), book: book())
        let t = try #require(r.transaction)
        #expect(t.merchant == "Unknown merchant")
        #expect(t.needsCheck)
    }

    /// Title/Subtitle/Body order the iOS 27 Notification-trigger design
    /// depends on: card, shop, amount, joined with newlines.
    @Test func titleSubtitleBodyOrderParsesCorrectly() {
        let parts = WalletTapText.parse("Visa Debit\nSeven Seeds\nA$4.50")
        #expect(parts.card == "Visa Debit")
        #expect(parts.merchant == "Seven Seeds")
        #expect(parts.amount == "A$4.50")
    }
}

/// "Check the Shortcut" (spec 2026-09-26, failsafe #11).
struct ApplePayHealthCheckTests {
    private let started = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func waitingBeforeAnythingArrivesOrTheTimeout() {
        let state = ApplePayHealthCheck.resolve(startedAt: started, lastReachedAt: nil, now: started.addingTimeInterval(5))
        #expect(state == .waiting)
    }

    @Test func reachedWhenAnArrivalIsAtOrAfterTheStart() {
        let reachedAt = started.addingTimeInterval(3)
        let state = ApplePayHealthCheck.resolve(startedAt: started, lastReachedAt: reachedAt, now: started.addingTimeInterval(5))
        #expect(state == .reached(reachedAt))
    }

    /// An arrival from before the check started (a stale flag from an
    /// earlier run) does not count as this check succeeding.
    @Test func anArrivalFromBeforeTheCheckStartedDoesNotCount() {
        let staleReach = started.addingTimeInterval(-60)
        let state = ApplePayHealthCheck.resolve(startedAt: started, lastReachedAt: staleReach, now: started.addingTimeInterval(5))
        #expect(state == .waiting)
    }

    @Test func timesOutAfter20Seconds() {
        let state = ApplePayHealthCheck.resolve(startedAt: started, lastReachedAt: nil, now: started.addingTimeInterval(20))
        #expect(state == .timedOut)
    }

    @Test func payloadParsesToTheKnownTestFields() {
        let parts = WalletTapText.parse(ApplePayHealthCheck.payloadText)
        #expect(parts.merchant == ApplePayHealthCheck.merchant)
        #expect(parts.amount == "A$0.01")
        #expect(parts.card == "Test Card")
    }

    @Test func runURLNamesTheShortcutAndCarriesThePayload() throws {
        let url = try #require(ApplePayHealthCheck.runURL)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "shortcuts")
        #expect(components.queryItems?.first { $0.name == "name" }?.value == ApplePayHealthCheck.shortcutName)
        #expect(components.queryItems?.first { $0.name == "text" }?.value == ApplePayHealthCheck.payloadText)
    }
}

/// "Needs a check": the note-marker convention (spec 2026-09-26, no schema
/// migration for this first pass) plus `ApplePayStatus`'s aggregate count.
@MainActor
struct NeedsCheckTests {
    private func tap(_ merchant: String, amount: Decimal = 0, note: String = "", at date: Date = .now) -> Transaction {
        Transaction(date: date, merchant: merchant, amount: amount, currencyCode: "AUD",
                   card: .other, category: .other, source: .tap, note: note)
    }

    @Test func aPlainPurchaseIsNotFlagged() {
        #expect(!tap("Coles", amount: 40).needsCheck)
    }

    @Test func aZeroAmountRowIsFlaggedEvenWithoutTheMarker() {
        #expect(tap("Coles", amount: 0).needsCheck)
    }

    @Test func aTaggedNoteIsFlaggedEvenWithARealAmount() {
        #expect(tap("Unknown merchant", amount: 12, note: "\(Transaction.needsCheckTag)Apple Pay sent no shop name. Tap to fix.").needsCheck)
    }

    @Test func editingTheNoteAwayUnflagsIt() {
        let t = tap("Unknown merchant", amount: 12, note: "\(Transaction.needsCheckTag)Apple Pay sent no shop name. Tap to fix.")
        t.note = "Actually it was the vending machine"
        #expect(!t.needsCheck)
    }

    @Test func statusCountsFlaggedRowsExcludingTestMerchants() {
        let flagged = tap("Unknown merchant", amount: 0, at: Date(timeIntervalSince1970: 1_790_000_000))
        let legacyTest = tap(LogPurchaseIntent.legacyTestMerchant, amount: 0, at: Date(timeIntervalSince1970: 1_790_000_100))
        let healthCheck = tap(ApplePayHealthCheck.merchant, amount: 0, at: Date(timeIntervalSince1970: 1_790_000_200))
        let demo = tap("Uber", amount: 0, note: DemoData.marker, at: Date(timeIntervalSince1970: 1_790_000_300))
        let clean = tap("Woolworths", amount: 40, at: Date(timeIntervalSince1970: 1_790_000_400))
        let count = ApplePayStatus.needsCheckCount(in: [flagged, legacyTest, healthCheck, demo, clean])
        #expect(count == 1)
    }

    @Test func needsCheckLineWording() {
        #expect(ApplePayStatus.needsCheckLine(count: 0) == nil)
        #expect(ApplePayStatus.needsCheckLine(count: 1) == "1 tap needs a check")
        #expect(ApplePayStatus.needsCheckLine(count: 3) == "3 taps need a check")
    }
}

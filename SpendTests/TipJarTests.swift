import Testing
import Foundation
@testable import Spend
import StoreKitTest
import StoreKit

/// Tip jar purchases against the local StoreKit configuration
/// `Spend/SortdTips.storekit` (no Apple account needed). Serialized: they
/// share one test session, the same way `ProStoreTests` did before it was
/// deleted with `ProStore` (overhaul sub-spec 1).
///
/// Contract for `Spend/Services/TipJar.swift`, which does not exist yet --
/// this whole file fails to compile until swift-builder adds it:
///
///     @MainActor @Observable final class TipJar {
///         enum Outcome { case thanked, cancelled, failed(Error) }
///         var products: [Product]
///         func load() async
///         func tip(_ product: Product) async -> Outcome
///     }
///
/// It finishes every verified transaction from `Transaction.updates` and
/// `Transaction.unfinished`, and stores nothing: no entitlement, no
/// `currentEntitlements`, no restore. In particular `TipJar` must expose no
/// Boolean the rest of the app can read as "the person tipped" or "the
/// person is Pro" -- there is no `isPro`, no `hasTipped`, nothing but
/// `products` and the two methods above. That's a contract for code review,
/// not something a compiler can check; it is asserted here only as this
/// doc comment.
@MainActor
@Suite(.serialized)
struct TipJarTests {
    private static let ids = [
        "com.kameshraj.sortd.tip.small",
        "com.kameshraj.sortd.tip.medium",
        "com.kameshraj.sortd.tip.large",
    ]

    private static func session() throws -> SKTestSession {
        let s = try SKTestSession(configurationFileNamed: "SortdTips")
        s.resetToDefaultState()
        s.clearTransactions()
        s.disableDialogs = true
        return s
    }

    private func expectThanked(_ outcome: TipJar.Outcome, sourceLocation: SourceLocation = #_sourceLocation) {
        guard case .thanked = outcome else {
            Issue.record("expected .thanked, got \(outcome)", sourceLocation: sourceLocation)
            return
        }
    }

    @Test func loadReturnsExactlyTheThreeTipsSortedByPrice() async throws {
        let s = try Self.session(); _ = s
        let jar = TipJar()
        await jar.load()
        #expect(Set(jar.products.map(\.id)) == Set(Self.ids))
        #expect(jar.products.count == 3)
        #expect(jar.products.map(\.price) == jar.products.map(\.price).sorted())
    }

    @Test func buyingSmallThanksAndFinishesTheTransaction() async throws {
        let s = try Self.session()
        let jar = TipJar()
        await jar.load()
        let small = try #require(jar.products.first { $0.id == "com.kameshraj.sortd.tip.small" })

        let outcome = await jar.tip(small)
        expectThanked(outcome)

        // A finished transaction is no longer in the unfinished queue.
        var unfinished: [StoreKit.Transaction] = []
        for await result in StoreKit.Transaction.unfinished {
            if case .verified(let t) = result { unfinished.append(t) }
        }
        #expect(!unfinished.contains { $0.productID == small.id })
        s.clearTransactions()
    }

    /// A real user cancel gives `.cancelled` -- that's the builder's
    /// handling of `Product.PurchaseResult.userCancelled`, which the
    /// StoreKit Testing harness has no way to simulate. What the harness
    /// *can* force is StoreKit 2 failing the purchase outright: with
    /// `failureError` set, that surfaces as a bare `StoreKitError.unknown`,
    /// not a user cancel. So this test pins the harness-reachable case: a
    /// failed purchase is `.failed(_)`, never `.thanked`, and finishes no
    /// transaction.
    @Test func aFailedPurchaseIsNotThanked() async throws {
        let s = try Self.session()
        s.failTransactionsEnabled = true
        s.failureError = .paymentCancelled
        defer { s.failTransactionsEnabled = false }
        let jar = TipJar()
        await jar.load()
        let small = try #require(jar.products.first { $0.id == "com.kameshraj.sortd.tip.small" })

        let outcome = await jar.tip(small)

        guard case .failed = outcome else {
            Issue.record("expected .failed, got \(outcome)")
            return
        }

        var unfinished: [StoreKit.Transaction] = []
        for await result in StoreKit.Transaction.unfinished {
            if case .verified(let t) = result { unfinished.append(t) }
        }
        #expect(!unfinished.contains { $0.productID == small.id })
        s.clearTransactions()
    }

    /// Consumable: buying the same tip twice both succeed.
    @Test func buyingTwiceWorksBecauseItsConsumable() async throws {
        let s = try Self.session()
        let jar = TipJar()
        await jar.load()
        let small = try #require(jar.products.first { $0.id == "com.kameshraj.sortd.tip.small" })

        expectThanked(await jar.tip(small))
        expectThanked(await jar.tip(small))
        s.clearTransactions()
    }
}

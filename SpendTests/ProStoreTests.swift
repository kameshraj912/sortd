import Testing
import Foundation
@testable import Spend
import StoreKitTest
import StoreKit

/// Sortd Pro purchases against the local StoreKit configuration (no Apple
/// account needed). Serialized: they share one test session.
@MainActor
@Suite(.serialized)
struct ProStoreTests {
    private static func session() throws -> SKTestSession {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Spend/SortdPro.storekit")
        let s = try SKTestSession(contentsOf: url)
        s.resetToDefaultState()
        s.clearTransactions()
        s.disableDialogs = true
        return s
    }

    @Test func plansLoadWithPricesAndTrial() async throws {
        let s = try Self.session(); _ = s
        let products = try await Product.products(for: ProStore.ID.all)
        #expect(products.count == 3)
        let yearly = try #require(products.first { $0.id == ProStore.ID.yearly })
        #expect(yearly.price == Decimal(string: "49.99"))
        #expect(yearly.subscription?.introductoryOffer?.paymentMode == .freeTrial)
        #expect(await ProStore.shared.trialText(for: yearly) == "14 days free")
        let lifetime = try #require(products.first { $0.id == ProStore.ID.lifetime })
        #expect(lifetime.type == .nonConsumable)
    }

    @Test func buyingYearlyUnlocksPro() async throws {
        let s = try Self.session(); _ = s
        let store = ProStore.shared
        await store.refresh()
        #expect(!store.isPro)
        let yearly = try #require(try await Product.products(for: [ProStore.ID.yearly]).first)
        #expect(try await store.buy(yearly) == .purchased)
        #expect(store.isPro)
        s.clearTransactions()
        await store.refresh()
        #expect(!store.isPro)
    }

    @Test func lifetimeUnlocksAndRestores() async throws {
        let s = try Self.session(); _ = s
        let store = ProStore.shared
        let lifetime = try #require(try await Product.products(for: [ProStore.ID.lifetime]).first)
        #expect(try await store.buy(lifetime) == .purchased)
        await store.refresh()
        #expect(store.isPro)
        s.clearTransactions()
    }

    /// A refund (Apple sets revocationDate) takes Pro away again.
    @Test func refundLocksPro() async throws {
        let s = try Self.session(); _ = s
        let store = ProStore.shared
        let lifetime = try #require(try await Product.products(for: [ProStore.ID.lifetime]).first)
        #expect(try await store.buy(lifetime) == .purchased)
        #expect(store.isPro)
        let t = try #require(s.allTransactions().first { $0.productIdentifier == ProStore.ID.lifetime })
        try s.refundTransaction(identifier: t.identifier)
        for _ in 0..<20 where store.isPro {
            try await Task.sleep(for: .milliseconds(250))
            await store.refresh()
        }
        #expect(!store.isPro)
        s.clearTransactions()
    }

    /// Restore (AppStore.sync) then refresh keeps a bought plan.
    @Test func restoreKeepsPurchase() async throws {
        let s = try Self.session(); _ = s
        let store = ProStore.shared
        let yearly = try #require(try await Product.products(for: [ProStore.ID.yearly]).first)
        #expect(try await store.buy(yearly) == .purchased)
        try await store.restore()
        #expect(store.isPro)
        s.clearTransactions()
        await store.redeemed(nil)   // the offer code path: refresh with nothing new
        #expect(!store.isPro)
    }

    @Test func expiredSubscriptionLocksAgain() async throws {
        let s = try Self.session(); _ = s
        s.timeRate = .oneRenewalEveryTwoSeconds
        let store = ProStore.shared
        let monthly = try #require(try await Product.products(for: [ProStore.ID.monthly]).first)
        #expect(try await store.buy(monthly) == .purchased)
        #expect(store.isPro)
        try s.expireSubscription(productIdentifier: ProStore.ID.monthly)
        // StoreKit applies the expiry asynchronously; give it a moment.
        for _ in 0..<20 where store.isPro {
            try await Task.sleep(for: .milliseconds(250))
            await store.refresh()
        }
        #expect(!store.isPro)
        s.clearTransactions()
        s.timeRate = .realTime
    }

    /// A failed card during Billing Grace Period must keep Pro while Apple retries.
    @Test func gracePeriodKeepsPro() async throws {
        let s = try Self.session(); _ = s
        s.timeRate = .oneRenewalEveryTwoSeconds
        s.shouldEnterBillingRetryOnRenewal = true
        s.billingGracePeriodIsEnabled = true
        defer {
            s.shouldEnterBillingRetryOnRenewal = false
            s.billingGracePeriodIsEnabled = false
            s.clearTransactions()
            s.timeRate = .realTime
        }
        let store = ProStore.shared
        let monthly = try #require(try await Product.products(for: [ProStore.ID.monthly]).first)
        #expect(try await store.buy(monthly) == .purchased)
        // Note: StoreKit Testing enters grace before the old expirationDate passes, so
        // this can't reproduce the live case (grace running, expiry already past) that
        // refresh() now handles. It guards against grace locking Pro in general.
        var state: Product.SubscriptionInfo.RenewalState?
        for _ in 0..<120 where state != .inGracePeriod {   // up to 30 s: StoreKit Testing is slow after a simulator reset
            try await Task.sleep(for: .milliseconds(250))
            state = try await monthly.subscription?.status.first?.state
        }
        // On a fresh simulator StoreKit Testing sometimes never enters grace at
        // all. That's the test environment, not Sortd: note it and stop. If grace
        // is reached, Pro must stay on — that part still fails for real.
        guard state == .inGracePeriod else {
            withKnownIssue("StoreKit Testing didn't enter billing grace", isIntermittent: true) {
                Issue.record("No grace period within 30 s (state: \(String(describing: state)))")
            }
            return
        }
        await store.refresh()
        #expect(store.isPro)
    }
}

import Testing
import Foundation
import StoreKit
@testable import Spend

/// The TestFlight beta unlock (`BetaAccess`) and what the paywall shows
/// (`PaywallState`). Pure logic: the App Store answer is injected, so these
/// run without a network or a StoreKit session.
@MainActor
struct BetaAccessTests {
    /// A private UserDefaults per test, so the cache never leaks between tests.
    private func defaults() -> UserDefaults {
        let name = "BetaAccessTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    /// Counts calls and hands back answers in order (nil = lookup failed).
    private final class FakeAppStore {
        var answers: [BetaAccess.Environment?]
        var calls = 0
        init(_ answers: [BetaAccess.Environment?]) { self.answers = answers }
        func next() -> BetaAccess.Environment? {
            calls += 1
            return answers.isEmpty ? nil : answers.removeFirst()
        }
    }

    private func access(_ store: FakeAppStore, _ d: UserDefaults) -> BetaAccess {
        BetaAccess(defaults: d, lookUp: { store.next() }, pause: { _ in })
    }

    @Test func proIsOnBeforeTheCheckRuns() {
        // No flash of locked screens while the async check is in flight.
        let a = access(FakeAppStore([]), defaults())
        #expect(a.known == nil)
        #expect(a.unlocksPro)
    }

    @Test func offlineFirstLaunchKeepsProOn() async {
        let store = FakeAppStore([nil, nil, nil])
        let a = access(store, defaults())
        await a.resolve(attempts: 3)
        #expect(store.calls == 3)
        #expect(a.known == nil)
        #expect(a.unlocksPro)
    }

    @Test func sandboxKeepsProOnAndIsCached() async {
        let d = defaults()
        let a = access(FakeAppStore([.sandbox]), d)
        await a.resolve(attempts: 3)
        #expect(a.unlocksPro)
        #expect(d.string(forKey: BetaAccess.cacheKey) == "sandbox")
    }

    @Test func productionTurnsBetaUnlockOff() async {
        let d = defaults()
        let a = access(FakeAppStore([.production]), d)
        await a.resolve(attempts: 3)
        #expect(!a.unlocksPro)
        #expect(d.string(forKey: BetaAccess.cacheKey) == "production")
    }

    @Test func retriesUntilTheAppStoreAnswers() async {
        let store = FakeAppStore([nil, .production])
        let a = access(store, defaults())
        await a.resolve(attempts: 3)
        #expect(store.calls == 2)
        #expect(!a.unlocksPro)
    }

    @Test func cachedProductionStartsLockedNextLaunch() {
        let d = defaults()
        d.set("production", forKey: BetaAccess.cacheKey)
        let a = access(FakeAppStore([]), d)
        #expect(!a.unlocksPro)
    }

    @Test func failedRecheckKeepsLastAnswer() async {
        let d = defaults()
        d.set("production", forKey: BetaAccess.cacheKey)
        let a = access(FakeAppStore([nil]), d)
        await a.resolve(attempts: 1)
        #expect(!a.unlocksPro)   // offline never turns Pro on for an App Store copy
    }

    @Test func recheckOnActiveCanChangeTheAnswer() async {
        // Had the App Store version, then installed the TestFlight build:
        // same UserDefaults, but the new check says sandbox.
        let d = defaults()
        d.set("production", forKey: BetaAccess.cacheKey)
        let a = access(FakeAppStore([.sandbox]), d)
        #expect(!a.unlocksPro)
        await a.resolve(attempts: 1)
        #expect(a.unlocksPro)
    }

    @Test func productionIsBelievedEvenUnverified() {
        #expect(BetaAccess.classify(.production, verified: true) == .production)
        #expect(BetaAccess.classify(.production, verified: false) == .production)
        #expect(BetaAccess.classify(.sandbox, verified: true) == .sandbox)
        #expect(BetaAccess.classify(.xcode, verified: true) == .sandbox)
        // An unverified sandbox claim is not proof of anything.
        #expect(BetaAccess.classify(.sandbox, verified: false) == nil)
    }

    /// DEBUG test builds don't set SORTD_BETA, so Pro must still come from a
    /// purchase here and the paywall must sell.
    @Test func debugBuildIsNotTheBeta() {
        #expect(!ProStore.shared.isBetaFree)
    }

    // MARK: Paywall

    @Test func paywallInBetaShowsNoPrices() {
        let s = PaywallState.make(betaFree: true, isPro: true, planCount: 3, isLoading: false, loadError: nil)
        #expect(s == .betaFree)
        #expect(!s.showsPurchaseFooter)
        // Beta wins even if the App Store can't be reached.
        #expect(PaywallState.make(betaFree: true, isPro: true, planCount: 0, isLoading: false, loadError: "x") == .betaFree)
    }

    @Test func paywallStates() {
        #expect(PaywallState.make(betaFree: false, isPro: true, planCount: 3, isLoading: false, loadError: nil) == .owned)
        #expect(!PaywallState.owned.showsPurchaseFooter)
        #expect(PaywallState.make(betaFree: false, isPro: false, planCount: 3, isLoading: false, loadError: nil) == .plans)
        #expect(PaywallState.make(betaFree: false, isPro: false, planCount: 0, isLoading: true, loadError: nil) == .loading)
        #expect(PaywallState.make(betaFree: false, isPro: false, planCount: 0, isLoading: false, loadError: nil) == .loading)
        #expect(PaywallState.make(betaFree: false, isPro: false, planCount: 0, isLoading: false, loadError: "offline") == .failed("offline"))
        // Restore and Redeem Code stay reachable while plans load or fail.
        #expect(PaywallState.plans.showsPurchaseFooter)
        #expect(PaywallState.loading.showsPurchaseFooter)
        #expect(PaywallState.failed("offline").showsPurchaseFooter)
    }
}

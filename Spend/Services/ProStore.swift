import Foundation
import StoreKit
import Observation

/// Sortd Pro: two subscriptions and a one-time purchase, sold through the
/// App Store (StoreKit 2). No server: entitlements come straight from the
/// App Store's signed transactions on the device.
///
/// Free forever: Apple Pay auto-logging, manual entry, Home, Activity, cards,
/// export and delete. Pro adds Gmail receipts, the receipt camera, Insights,
/// Subscriptions & bills with reminders, and category budgets.
@MainActor
@Observable
final class ProStore {
    static let shared = ProStore()

    enum ID {
        static let monthly = "com.kameshraj.spend.pro.monthly"
        static let yearly = "com.kameshraj.spend.pro.yearly"
        static let lifetime = "com.kameshraj.spend.pro.lifetime"
        static let all = [yearly, monthly, lifetime]
    }

    enum Feature: String, CaseIterable, Identifiable {
        case gmail, camera, insights, recurring, budgets
        var id: String { rawValue }
        /// What this build offers. Gmail is left out of the App Store build (`Features.gmail`).
        static var available: [Feature] { allCases.filter { $0 != .gmail || Features.gmail } }
        var title: String {
            switch self {
            case .gmail: "Gmail receipts"
            case .camera: "Receipt camera"
            case .insights: "Insights"
            case .recurring: "Subscriptions & bills"
            case .budgets: "Category budgets"
            }
        }
        var detail: String {
            switch self {
            case .gmail: "Deliveries, rides and app stores, read from your inbox on this iPhone."
            case .camera: "Point at a paper receipt. Sortd fills in the shop and total."
            case .insights: "This month next to last month, by day and by category."
            case .recurring: "Every repeat charge found, with a reminder the day before."
            case .budgets: "Limits for eating out, shopping or anything else."
            }
        }
        var symbol: String {
            switch self {
            case .gmail: "envelope"
            case .camera: "doc.text.viewfinder"
            case .insights: "chart.bar"
            case .recurring: "arrow.triangle.2.circlepath"
            case .budgets: "gauge.with.dots.needle.33percent"
            }
        }
    }

    private(set) var products: [Product] = []
    private(set) var purchasedIDs: Set<String> = []
    private(set) var loadError: String?
    private(set) var isLoading = false

    /// Unlocks everything. Also true in DEBUG with SPEND_PRO=1 (screenshots),
    /// and in a SORTD_BETA build until the App Store says this copy is a real
    /// App Store download (`isBetaFree`).
    var isPro: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SPEND_PRO"] == "1" { return true }
        if ProcessInfo.processInfo.environment["SPEND_PRO"] == "0" { return false }
        #endif
        if isBetaFree { return true }
        #if DEBUG
        // Given away rather than bought. Debug builds only (App Review 3.1.1).
        if CompedPro.isActive() { return true }
        #endif
        return !purchasedIDs.isEmpty
    }

    /// True in the TestFlight beta, where everything is free. The paywall and
    /// onboarding use this to drop prices, trials and upsells.
    ///
    /// SORTD_BETA is set on Release in the project file. Remove it before the
    /// App Store build or App Review (which runs in the sandbox) never sees
    /// the paywall work. `scripts/preflight.sh --appstore` checks this.
    var isBetaFree: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SPEND_BETA"] == "1" { return true }
        #endif
        #if SORTD_BETA
        return beta.unlocksPro
        #else
        return false
        #endif
    }

    /// Decides the beta unlock from the App Store environment. Always built so
    /// tests can reach it; only consulted when SORTD_BETA is set.
    let beta = BetaAccess()

    private var updates: Task<Void, Never>?
    private var statusUpdates: Task<Void, Never>?
    private var expiryCheck: Task<Void, Never>?

    private init() {
        // New purchases, renewals, refunds, revocations, Ask to Buy approvals,
        // Family Sharing changes and offer codes redeemed anywhere (the App
        // Store app, a redemption link, our own sheet) all arrive here.
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        // Renewal state changes (billing retry, grace period, auto-renew off).
        statusUpdates = Task { [weak self] in
            for await _ in Product.SubscriptionInfo.Status.updates {
                await self?.refresh()
            }
        }
        Task {
            // Anything bought or redeemed while the app wasn't running.
            for await result in StoreKit.Transaction.unfinished {
                if case .verified(let t) = result { await t.finish() }
            }
            #if SORTD_BETA
            await beta.resolve(attempts: 3)
            #endif
            await refresh()
            await load()
        }
    }

    func product(_ id: String) -> Product? { products.first { $0.id == id } }

    func load() async {
        guard products.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let found = try await Product.products(for: ID.all)
            products = ID.all.compactMap { id in found.first { $0.id == id } }
            loadError = products.isEmpty ? "The App Store didn't return any plans. Check your connection and try again." : nil
        } catch {
            loadError = "Couldn't reach the App Store. Check your connection and try again."
        }
    }

    /// Current entitlements from the App Store (signed on the device).
    ///
    /// Called at launch, after a purchase, restore or redeemed code, on every
    /// StoreKit update, and each time the app becomes active (SpendApp).
    /// `currentEntitlements` already leaves out refunded, expired and
    /// upgraded-away transactions, and includes ones shared by a Family
    /// Sharing organiser (`ownershipType == .familyShared`), so those count.
    /// Pro follows the Apple Account to every device through StoreKit itself.
    func refresh() async {
        #if SORTD_BETA
        // One quick look, no retries: a tester who installed offline gets the
        // answer the next time they open the app with a connection.
        Task { await beta.resolve(attempts: 1) }
        #endif
        var ids: Set<String> = []
        var nextExpiry: Date?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            // Subscriptions here are already subscribed or in Billing Grace Period.
            // A grace-period one has a past expirationDate but must keep Pro.
            if t.productType != .autoRenewable, let exp = t.expirationDate, exp < .now { continue }
            ids.insert(t.productID)
            if let exp = t.expirationDate, exp > .now { nextExpiry = min(nextExpiry ?? exp, exp) }
        }
        purchasedIDs = ids
        scheduleExpiryCheck(at: nextExpiry)
    }

    /// Expiry sends no StoreKit update. Look again just after the earliest
    /// expiry so Pro doesn't stay on while the app sits open.
    private func scheduleExpiryCheck(at date: Date?) {
        expiryCheck?.cancel()
        guard let date else { return }
        expiryCheck = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(date.timeIntervalSinceNow, 0) + 1))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    enum Outcome { case purchased, pending, cancelled }

    func buy(_ product: Product) async throws -> Outcome {
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let t) = result else { throw StoreError.unverified }
            await t.finish()
            await refresh()
            if remindsBeforeTrialEnds, t.offer?.paymentMode == .freeTrial, let end = t.expirationDate {
                // Not awaited: the permission prompt mustn't hold up the sheet closing.
                let price = "\(product.displayPrice) \(PaywallPlan.kind(for: product.id) == .monthly ? "a month" : "a year")"
                Task { await Reminders.scheduleTrialEnding(endsAt: end, price: price) }
            }
            return .purchased
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: return .cancelled
        }
    }

    /// Restore Purchases: asks the App Store to re-send this Apple Account's
    /// transactions, then reads entitlements again.
    func restore() async throws {
        try await AppStore.sync()
        await refresh()
    }

    /// After the offer code sheet closes. The redeemed transaction also comes
    /// through `Transaction.updates`; finishing twice is harmless.
    func redeemed(_ result: VerificationResult<StoreKit.Transaction>?) async {
        if case .verified(let t) = result { await t.finish() }
        await refresh()
    }

    enum StoreError: LocalizedError {
        case unverified
        var errorDescription: String? { "The App Store couldn't confirm this purchase. Please try again." }
    }

    /// The trial timeline promises a notification two days before the end.
    /// Tests turn it off so no permission prompt appears.
    var remindsBeforeTrialEnds = true

    /// The plans as the paywall shows them, with the free trial only when
    /// this Apple Account can still get it.
    func paywallPlans() async -> [PaywallPlan] {
        var plans: [PaywallPlan] = []
        for p in products {
            plans.append(PaywallPlan(id: p.id, kind: PaywallPlan.kind(for: p.id), displayPrice: p.displayPrice,
                                     price: p.price, format: p.priceFormatStyle,
                                     trial: await trialPeriod(for: p), product: p))
        }
        return plans
    }

    /// The free trial this person can still get on a plan, if any.
    func trialPeriod(for product: Product) async -> TrialPeriod? {
        guard let sub = product.subscription, let offer = sub.introductoryOffer,
              offer.paymentMode == .freeTrial, await sub.isEligibleForIntroOffer else { return nil }
        return TrialPeriod(offer.period)
    }

    /// Whether this person can still get the free trial on a plan.
    func trialText(for product: Product) async -> String? {
        guard let sub = product.subscription, let offer = sub.introductoryOffer,
              await sub.isEligibleForIntroOffer, offer.paymentMode == .freeTrial else { return nil }
        return "\(Self.describe(offer.period)) free"
    }

    static func describe(_ p: Product.SubscriptionPeriod) -> String {
        let n = p.value
        switch p.unit {
        case .day: return n == 7 ? "1 week" : "\(n) days"
        case .week: return n == 1 ? "1 week" : "\(n * 7) days"
        case .month: return n == 1 ? "1 month" : "\(n) months"
        case .year: return n == 1 ? "1 year" : "\(n) years"
        @unknown default: return ""
        }
    }
}

/// Whether a SORTD_BETA build gives Pro away.
///
/// The rule: Pro is on until the App Store has positively said this copy is
/// a production (App Store) download. So a tester never sees locked screens
/// flash while the async check runs, and a first launch offline doesn't lock
/// them out. The last answer is cached so the next launch starts right.
///
/// A production answer is not made permanent: someone who had the App Store
/// version and then joins TestFlight keeps the same UserDefaults, and must
/// get the beta unlock once the new check says sandbox.
///
/// The one gap this leaves: a SORTD_BETA build shipped to the App Store by
/// mistake would give Pro away on a first launch that can't reach the App
/// Store. The preflight script blocks that build.
@MainActor
@Observable
final class BetaAccess {
    enum Environment: String, Sendable { case production, sandbox }

    static let cacheKey = "proStoreEnvironment"

    /// The last environment the App Store confirmed. Nil when never known.
    private(set) var known: Environment?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let lookUp: () async -> Environment?
    @ObservationIgnored private let pause: (Duration) async -> Void
    @ObservationIgnored private var checking = false

    /// - Parameters:
    ///   - lookUp: The App Store's answer, or nil when it couldn't give one
    ///     (offline, error, unverifiable sandbox).
    ///   - pause: Waits between tries. Tests pass a no-op.
    init(defaults: UserDefaults = .standard,
         lookUp: @escaping () async -> Environment? = BetaAccess.appStoreLookUp,
         pause: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.defaults = defaults
        self.lookUp = lookUp
        self.pause = pause
        known = defaults.string(forKey: Self.cacheKey).flatMap(Environment.init(rawValue:))
    }

    var unlocksPro: Bool { known != .production }

    /// Asks the App Store, trying `attempts` times with a growing wait. A
    /// failed look keeps whatever was known before.
    func resolve(attempts: Int) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        let tries = max(attempts, 1)
        for attempt in 0..<tries {
            if let env = await lookUp() {
                known = env
                defaults.set(env.rawValue, forKey: Self.cacheKey)
                return
            }
            if attempt < tries - 1 { await pause(.seconds(2 << attempt)) }
        }
    }

    /// Production is believed even unverified: the worst a forged
    /// "production" does is lock the forger out of a free beta. Sandbox only
    /// counts when Apple's signature checks out.
    nonisolated static func classify(_ environment: AppStore.Environment, verified: Bool) -> Environment? {
        if environment == .production { return .production }
        return verified ? .sandbox : nil
    }

    static func appStoreLookUp() async -> Environment? {
        guard let result = try? await AppTransaction.shared else { return nil }
        switch result {
        case .verified(let app): return classify(app.environment, verified: true)
        case .unverified(let app, _): return classify(app.environment, verified: false)
        }
    }
}

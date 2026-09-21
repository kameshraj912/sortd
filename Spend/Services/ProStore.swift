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
    /// and in a SORTD_BETA build running in the App Store sandbox, so
    /// TestFlight testers can reach every feature before the products exist.
    var isPro: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SPEND_PRO"] == "1" { return true }
        if ProcessInfo.processInfo.environment["SPEND_PRO"] == "0" { return false }
        #endif
        #if SORTD_BETA
        if isSandboxBuild { return true }
        #endif
        #if DEBUG
        // Given away rather than bought. Debug builds only (App Review 3.1.1).
        if CompedPro.isActive() { return true }
        #endif
        return !purchasedIDs.isEmpty
    }

    #if SORTD_BETA
    /// True when this build runs against the App Store sandbox — TestFlight or
    /// a local run. Resolved once at launch because the check is async. A real
    /// App Store purchaser reports `.production`, so this never gives Pro away.
    ///
    /// SORTD_BETA is set on Release in the project file. Remove it before the
    /// App Store build or App Review never sees the paywall work.
    private(set) var isSandboxBuild = false

    /// `AppTransaction.shared` can need the network the first time it is read,
    /// so a cold first launch on a plane would otherwise lock a tester out of
    /// every Pro feature. Retry a few times before giving up.
    private func resolveEnvironment() async {
        for attempt in 0..<3 {
            if let result = try? await AppTransaction.shared,
               case .verified(let app) = result {
                isSandboxBuild = app.environment != .production
                return
            }
            if attempt < 2 {
                try? await Task.sleep(for: .seconds(2 << attempt))
            }
        }
    }
    #endif

    private var updates: Task<Void, Never>?

    private init() {
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        Task {
            #if SORTD_BETA
            await resolveEnvironment()
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
    func refresh() async {
        var ids: Set<String> = []
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let t) = result, t.revocationDate == nil else { continue }
            // Subscriptions here are already subscribed or in Billing Grace Period.
            // A grace-period one has a past expirationDate but must keep Pro.
            if t.productType != .autoRenewable, let exp = t.expirationDate, exp < .now { continue }
            ids.insert(t.productID)
        }
        purchasedIDs = ids
    }

    enum Outcome { case purchased, pending, cancelled }

    func buy(_ product: Product) async throws -> Outcome {
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let t) = result else { throw StoreError.unverified }
            await t.finish()
            await refresh()
            return .purchased
        case .pending: return .pending
        case .userCancelled: return .cancelled
        @unknown default: return .cancelled
        }
    }

    func restore() async throws {
        try await AppStore.sync()
        await refresh()
    }

    enum StoreError: LocalizedError {
        case unverified
        var errorDescription: String? { "The App Store couldn't confirm this purchase. Please try again." }
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

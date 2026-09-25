import Foundation
import StoreKit
import Observation

/// The tip jar. Sortd is free; this is the one place money changes hands.
///
/// Three consumable tips, sold through the App Store (StoreKit 2). A tip
/// unlocks nothing and is remembered nowhere: no entitlement is read or
/// stored, and there is no restore. Every verified transaction is finished,
/// whether it came from `tip(_:)`, `Transaction.updates` or
/// `Transaction.unfinished`, so the App Store stops re-sending it.
@MainActor
@Observable
final class TipJar {
    static let shared = TipJar()

    enum ID {
        static let small = "com.kameshraj.spend.tip.small"
        static let medium = "com.kameshraj.spend.tip.medium"
        static let large = "com.kameshraj.spend.tip.large"
        static let all = [small, medium, large]
    }

    enum Outcome {
        case thanked
        case cancelled
        case failed(Error)
    }

    enum TipError: LocalizedError {
        case unverified
        case pending
        var errorDescription: String? {
            switch self {
            case .unverified: "The App Store couldn't confirm this tip. Please try again."
            case .pending: "Waiting for approval, like Ask to Buy. Thank you either way."
            }
        }
    }

    /// The three tips, cheapest first. Empty until `load()` has run.
    private(set) var products: [Product] = []
    /// Why `products` is empty after a load, in plain words. Nil while
    /// loading or when the load worked.
    private(set) var loadError: String?

    @ObservationIgnored private var updates: Task<Void, Never>?
    /// The load in flight, shared so launch and the sheet never race.
    @ObservationIgnored private var loading: Task<Void, Never>?

    init() {}

    /// Call once at launch: finishes anything left over from a past run,
    /// listens for transactions that arrive while the app runs, then loads
    /// the prices. Safe to call again; later calls do nothing.
    func start() {
        guard updates == nil else { return }
        updates = Task {
            for await result in StoreKit.Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
            }
        }
        Task {
            for await result in StoreKit.Transaction.unfinished {
                if case .verified(let t) = result { await t.finish() }
            }
            await load()
        }
    }

    /// Loads the prices. A second call while one is running waits for that
    /// one. A failed load keeps whatever was loaded before.
    func load() async {
        if let loading { return await loading.value }
        let task = Task { await fetch() }
        loading = task
        await task.value
        loading = nil
    }

    private func fetch() async {
        loadError = nil
        do {
            let found = try await Product.products(for: ID.all)
            if found.isEmpty {
                if products.isEmpty { loadError = "The App Store didn't return the tips. Check your connection and try again." }
            } else {
                products = found.sorted { $0.price < $1.price }
            }
        } catch {
            if products.isEmpty { loadError = "Couldn't reach the App Store. Check your connection and try again." }
        }
    }

    /// The last part of a tip's product id ("com.kameshraj.spend.tip.small"
    /// gives "small"). For analytics; the price never goes anywhere.
    nonisolated static func size(of productID: String) -> String {
        String(productID.split(separator: ".").last ?? "unknown")
    }

    /// Buys one tip and finishes it. Cancelling is not an error. The App
    /// Store sheet makes the scene inactive, so it runs under `SystemPrompt`
    /// to keep the privacy cover off it.
    func tip(_ product: Product) async -> Outcome {
        do {
            switch try await SystemPrompt.shared.showing({ try await product.purchase() }) {
            case .success(let result):
                guard case .verified(let t) = result else { return .failed(TipError.unverified) }
                await t.finish()
                // Which tip, never the price: "small", "medium" or "large".
                Analytics.shared.track(.tipLeft, ["size": .string(Self.size(of: product.id))])
                return .thanked
            case .pending:
                return .failed(TipError.pending)
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            if case StoreKitError.userCancelled = error { return .cancelled }
            return .failed(error)
        }
    }
}

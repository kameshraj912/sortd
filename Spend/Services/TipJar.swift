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

    func load() async {
        loadError = nil
        do {
            let found = try await Product.products(for: ID.all)
            products = found.sorted { $0.price < $1.price }
            if products.isEmpty { loadError = "The App Store didn't return the tips. Check your connection and try again." }
        } catch {
            products = []
            loadError = "Couldn't reach the App Store. Check your connection and try again."
        }
    }

    /// Buys one tip and finishes it. Cancelling is not an error.
    func tip(_ product: Product) async -> Outcome {
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let t) = result else { return .failed(TipError.unverified) }
                await t.finish()
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

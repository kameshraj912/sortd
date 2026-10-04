import Foundation
import Network
import CloudKit
import SwiftData

/// Whether the phone can reach the internet, and a way to carry on when it
/// comes back. A thin wrapper over `NWPathMonitor`: it only says "online" or
/// "offline". It never queues work itself. The things that wait for a
/// connection already keep their own pending state (a purchase with no rate,
/// the iCloud backup that is behind, queued account deletes), and the app
/// asks each of them to try again when `isOnline` turns true again
/// (`RootView`, `Connectivity.catchUp`).
///
/// `isOnline` is injectable, so tests set it by hand with `set(isOnline:)`.
@MainActor
@Observable
final class Connectivity {
    static let shared = Connectivity()

    private(set) var isOnline: Bool
    /// How many times the phone has gone from offline to online since launch.
    private(set) var reconnects = 0
    /// Called on each offline-to-online change, after `isOnline` is true.
    @ObservationIgnored var onReconnect: (() -> Void)?
    @ObservationIgnored private var monitor: NWPathMonitor?

    /// Starts online: the monitor reports the real state within a moment, and
    /// a wrong "offline" at launch would show a message that isn't true.
    init(isOnline: Bool = true) {
        self.isOnline = isOnline
    }

    /// Starts watching the network. Safe to call twice.
    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.set(isOnline: online) }
        }
        monitor.start(queue: DispatchQueue(label: "com.kameshraj.sortd.connectivity", qos: .utility))
        self.monitor = monitor
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }

    /// The monitor's callback, and the test hook.
    func set(isOnline new: Bool) {
        let old = isOnline
        guard new != old else { return }
        isOnline = new
        if Self.isReconnect(from: old, to: new) {
            reconnects += 1
            onReconnect?()
        }
    }

    nonisolated static func isReconnect(from old: Bool, to new: Bool) -> Bool { !old && new }

    // MARK: - Plain words for being offline

    nonisolated static let offlineMessage = "You're offline. Try again when you're connected."

    /// True when the error is the network being down or too weak to finish,
    /// not something a server said no to.
    nonisolated static func isNetworkDown(_ error: Error) -> Bool {
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .dnsLookupFailed, .timedOut, .dataNotAllowed, .internationalRoamingOff:
                return true
            default:
                return false
            }
        }
        if let ck = error as? CKError {
            return ck.code == .networkUnavailable || ck.code == .networkFailure
        }
        if let failure = error as? CloudKitBackupStore.Failure {
            return failure.code == .networkUnavailable || failure.code == .networkFailure
        }
        if let account = error as? AccountError { return account == .offline }
        return false
    }

    /// The one sentence to show for a failed network call: the offline
    /// message when the network was the cause, otherwise nil so the caller
    /// keeps its own words. Never a raw error string.
    nonisolated static func plainMessage(for error: Error) -> String? {
        isNetworkDown(error) ? offlineMessage : nil
    }

    /// What to say before starting something that needs the network. Nil
    /// when online.
    nonisolated static func blockedMessage(isOnline: Bool) -> String? {
        isOnline ? nil : offlineMessage
    }
}

extension Connectivity {
    /// The phone is back online. Each job keeps its own "pending" state and
    /// retries here: purchases with no rate (`FXService.backfill`), a backup
    /// that is behind, a Delete All Data that couldn't reach iCloud, queued
    /// account deletes, and Google token revokes.
    static func catchUp(in context: ModelContext) async {
        Task { await GoogleAuth.retryPendingRevokes() }
        await FXService.ensureConverted(in: context)
        await FXService.backfill(in: context)
        #if SORTD_SIGNIN
        await AccountStore.shared.retryPendingDeletes()
        #endif
        #if SORTD_ICLOUD
        await CloudBackup.shared.retryPendingDelete()
        await CloudBackup.shared.resumeAfterReconnect(from: context)
        #endif
    }
}

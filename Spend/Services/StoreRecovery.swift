import Foundation
import SwiftData
import Observation

/// What the recovery screen does when the store cannot be opened (see
/// `SpendStore.openFailure`). Every way out ends in a new store, so the app
/// asks the person to close it and open it again: the rest of the launch
/// (widgets, backups, cards) runs only on a store that opened.
///
/// Nothing is deleted. The unopenable store's files are moved to
/// `Recovered stores` beside them, so support can still look at them.
@MainActor @Observable
final class StoreRecovery {
    enum Phase: Equatable {
        case choosing
        case working
        /// A way out worked. The text says what to do next.
        case finished(String)
        /// A way out did not work; the text says why, in plain words.
        case failed(String)
    }

    private(set) var phase: Phase = .choosing

    /// Held so the new store stays open until the app is closed.
    @ObservationIgnored private var fresh: ModelContainer?

    nonisolated static let closeAndReopen = "Close Sortd completely, then open it again."

    /// "Start Fresh": an empty store, nothing restored.
    func startFresh() {
        guard phase != .working else { return }
        do {
            fresh = try SpendStore.setAsideAndOpenEmpty()
            phase = .finished("Sortd is ready to start again. " + Self.closeAndReopen)
        } catch {
            fail(error, where: "StoreRecovery.startFresh")
        }
    }

    /// "Restore from iCloud". The backup is read first: the old store is only
    /// set aside once the backup is known to open.
    #if SORTD_ICLOUD
    func restoreFromICloud() async {
        guard phase != .working else { return }
        phase = .working
        do {
            guard try await CloudBackup.shared.contents() != nil else {
                phase = .failed("There's no backup in iCloud for this Apple Account. Try a file, or start fresh.")
                return
            }
            let container = try SpendStore.setAsideAndOpenEmpty()
            fresh = container
            let added = try await CloudBackup.shared.restore(into: container.mainContext, mode: .replace)
            phase = .finished(Self.restoredMessage(added))
        } catch {
            fail(error, where: "StoreRecovery.restoreFromICloud")
        }
    }
    #endif

    /// "Restore from a File": a `.sortdbackup` the person saved earlier.
    func restoreFromFile(_ picked: Result<URL, Error>) async {
        guard phase != .working else { return }
        phase = .working
        do {
            let url = try picked.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard Backup.contents(of: data) != nil else {
                phase = .failed("That file isn't a Sortd backup.")
                return
            }
            let container = try SpendStore.setAsideAndOpenEmpty()
            fresh = container
            let result = try Backup.restore(data, mode: .replace, into: container.mainContext)
            phase = .finished(Self.restoredMessage(result.added))
        } catch {
            fail(error, where: "StoreRecovery.restoreFromFile")
        }
    }

    /// Back to the choices after a failure.
    func tryAgain() {
        if case .failed = phase { phase = .choosing }
    }

    nonisolated static func restoredMessage(_ count: Int) -> String {
        "\(count) purchase\(count == 1 ? " is" : "s are") back. " + closeAndReopen
    }

    private func fail(_ error: Error, where place: String) {
        ErrorLog.report(error, where: place)
        let why = Connectivity.plainMessage(for: error) ?? error.localizedDescription
        // Once the old store was set aside, an empty one took its place.
        let aside = fresh == nil ? "" : " Sortd has started with an empty store, and your old one is kept aside for support."
        phase = .failed(why + aside)
    }
}

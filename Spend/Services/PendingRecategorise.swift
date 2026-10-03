import Foundation
import SwiftData
import Observation

/// The Undo window behind "Moved 12 others at Coles". One shared copy, so a
/// change made on the detail screen still offers Undo on Activity after
/// going back, for the rest of the window (the same shape as
/// `PendingDeletes`). The change itself is already saved; this only holds
/// what is needed to reverse it.
///
/// When the window ends `closing` turns on: the toast fades but stays in
/// the tree and keeps taking taps. Only after `fade` is the record dropped.
@MainActor @Observable
final class PendingRecategorise {
    static let shared = PendingRecategorise()

    let window: Duration
    let fade: Duration
    private(set) var change: RecategoriseChange?
    /// True while the toast fades out at the end of the window.
    private(set) var closing = false
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(window: Duration = .seconds(8), fade: Duration = .milliseconds(350)) {
        self.window = window
        self.fade = fade
    }

    /// "Moved 12 others at Coles"; nil when nothing is staged.
    var text: String? { change?.toastText }

    /// Offers Undo for `change`. A change that moved nobody else has
    /// nothing to say: it is not staged. A newer change replaces the older
    /// one (its own undo is gone; the store already has it).
    func stage(_ change: RecategoriseChange) {
        timer?.cancel()
        closing = false
        guard change.toastText != nil else { self.change = nil; return }
        self.change = change
        timer = Task { [weak self, window, fade] in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled, let self, self.change == change else { return }
            self.closing = true
            try? await Task.sleep(for: fade)
            guard !Task.isCancelled, self.change == change, self.closing else { return }
            self.change = nil
            self.closing = false
        }
    }

    /// Puts every moved purchase and the rule back, even mid-fade.
    func undo(in context: ModelContext) {
        guard let change else { return }
        timer?.cancel()
        timer = nil
        do {
            try TransactionLogger.undo(change, in: context)
        } catch {
            log.error("Recategorise undo failed: \(error.localizedDescription)")
            ErrorLog.report(error, where: "PendingRecategorise.undo")
        }
        self.change = nil
        closing = false
        Analytics.shared.track(.purchaseUndone, ["count": .int(change.moved.count)])
    }

    /// Drops the record without undoing.
    func dismiss() {
        timer?.cancel()
        timer = nil
        change = nil
        closing = false
    }
}

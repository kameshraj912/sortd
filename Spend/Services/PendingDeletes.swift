import Foundation
import SwiftData
import Observation

/// Purchases swiped away on the Activity list but not yet deleted, so Undo
/// can bring them back. The rows leave the list as soon as they are staged;
/// nothing is written to the store until `commit(in:)`.
///
/// Each new stage restarts the window. When it ends, `onExpire` runs on the
/// main actor. Nothing is committed here: the view fades its toast (kept in
/// the tree, still taking taps) and calls `commit(in:)` once the fade ends,
/// so a drawn "Undo" button always works.
@MainActor @Observable
final class PendingDeletes {
    /// How long Undo stays available after the last swipe. Mail and Photos
    /// give about this long.
    let window: Duration
    private(set) var items: [Transaction] = []
    /// When the current window ends; nil when nothing is staged.
    private(set) var deadline: ContinuousClock.Instant?
    @ObservationIgnored private var timer: Task<Void, Never>?

    init(window: Duration = .seconds(8)) {
        self.window = window
    }

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    /// "Deleted Woolworths" or "Deleted 2 purchases".
    var text: String {
        if items.count == 1, let t = items.first { return "Deleted \(t.merchant)" }
        return "Deleted \(items.count) purchases"
    }

    /// Hide the row now and start (or restart) the window. `onExpire` runs
    /// once when the window ends unless `undo()` or `commit(in:)` comes first.
    /// Returns false, and changes nothing, for a row that is already staged.
    @discardableResult
    func stage(_ t: Transaction, onExpire: @escaping @MainActor () -> Void) -> Bool {
        guard !items.contains(where: { $0.persistentModelID == t.persistentModelID }) else { return false }
        items.append(t)
        timer?.cancel()
        let ends = ContinuousClock.now + window
        deadline = ends
        timer = Task { [weak self] in
            try? await Task.sleep(until: ends)
            guard !Task.isCancelled, let self, self.deadline == ends else { return }
            self.deadline = nil
            onExpire()
        }
        return true
    }

    /// Bring every staged row back.
    func undo() {
        cancelTimer()
        guard !items.isEmpty else { return }
        Analytics.shared.track(.purchaseUndone, ["count": .int(items.count)])
        items = []
    }

    /// Delete and save every staged row. A no-op when nothing is staged.
    func commit(in context: ModelContext) {
        cancelTimer()
        guard !items.isEmpty else { return }
        let gone = items
        items = []
        Analytics.shared.track(.purchaseDeleted, ["count": .int(gone.count)])
        for t in gone { context.delete(t) }
        do {
            try context.save()
        } catch {
            log.error("Pending delete save failed: \(error.localizedDescription)")
            ErrorLog.report(error, where: "PendingDeletes.commit")
        }
        WidgetBridge.refresh(from: context)
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
        deadline = nil
    }
}

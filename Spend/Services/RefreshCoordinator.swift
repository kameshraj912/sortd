import Foundation
import SwiftData

/// What pull-to-refresh runs on Home and Activity: the same "check for
/// anything new" pass `SpendApp` runs when the app becomes active (Gmail,
/// FX, widgets) — just on demand, from a pull instead of a scene-phase change.
@MainActor
enum RefreshCoordinator {
    /// What changed, for the status line under the pull-to-refresh spinner.
    struct Result: Equatable {
        var newPurchases: Int = 0
    }

    /// Shared with whichever call started it, so a pull on Home while the
    /// scene-phase sync (or a pull on Activity) is already running never
    /// starts a second one — both just await the one in flight.
    private static var running: Task<Result, Never>?

    @discardableResult
    static func refresh(in context: ModelContext, force: Bool = false) async -> Result {
        if let running { return await running.value }
        let task = Task<Result, Never> {
            defer { running = nil }
            // Fix a stale home-currency conversion before anything new is
            // imported, same order SpendApp uses on becoming active.
            await FXService.ensureConverted(in: context)
            // Gmail receipts are Pro-gated and account-gated inside
            // GmailSync itself; nothing to duplicate here.
            let summary = await GmailSync.syncAll(in: context, force: force)
            // Cheap safety net: fills in anything still missing a rate.
            // FXService only calls the network for what's actually pending.
            await FXService.backfill(in: context)
            WidgetBridge.refresh(from: context)
            return Result(newPurchases: summary.added)
        }
        running = task
        return await task.value
    }
}

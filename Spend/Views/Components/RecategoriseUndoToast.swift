import SwiftUI
import SwiftData

/// "Moved 12 others at Coles · Undo", from the shared `PendingRecategorise`
/// window. The detail screen and Activity both show it, so going back
/// keeps the Undo alive for the rest of the window. While the window ends
/// the toast fades in place and still takes taps; only after the fade is
/// it removed (the `PendingDeletes` pattern).
struct RecategoriseUndoToast: View {
    @Environment(\.modelContext) private var context
    private let pending = PendingRecategorise.shared
    /// Counted here, not on the shared holder: the detail screen and
    /// Activity each hold a toast, and only the one tapped should buzz.
    @State private var undone = 0

    var body: some View {
        Group {
            if let text = pending.text {
                UndoToast(text: text, symbol: "tag") { undo() }
                    .opacity(pending.closing ? 0 : 1)
                    .offset(y: pending.closing ? 40 : 0)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: pending.closing)
        .animation(.spring(duration: 0.35), value: pending.text)
        .feedback(.undo, trigger: undone)
    }

    private func undo() {
        pending.undo(in: context)
        undone += 1
        AccessibilityNotification.Announcement("Moved back").post()
    }
}

extension View {
    /// Shows the shared recategorise Undo toast over the bottom of a screen.
    func recategoriseUndoToast(bottomPadding: CGFloat = 12) -> some View {
        overlay(alignment: .bottom) {
            RecategoriseUndoToast().padding(.bottom, bottomPadding)
        }
    }
}

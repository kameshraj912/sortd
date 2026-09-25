import SwiftUI
import SwiftData

/// What a pull-to-refresh actually did.
///
/// Home and Activity both used to run the sync and throw the result away, so
/// the one gesture people repeat every day ended with the screen looking
/// exactly as it did before — the same whether three purchases arrived, none
/// did, or the sync failed.
struct RefreshNote: Equatable {
    let text: String
    let ok: Bool

    /// Runs the whole refresh and says how it went.
    @MainActor
    static func run(in context: ModelContext) async -> RefreshNote {
        let summary = await GmailSync.syncAll(in: context)
        await FXService.ensureConverted(in: context)

        if summary.failed > 0 {
            return RefreshNote(text: "Couldn't check your email. Pull down to try again.", ok: false)
        }
        if !Features.gmail || GmailSync.accounts.isEmpty {
            // Nothing to sync is not a failure, and saying "0 new" would be
            // misleading when no inbox is connected at all.
            return RefreshNote(text: "Up to date", ok: true)
        }
        let found = summary.added + summary.merged + summary.refunds
        return RefreshNote(text: found == 0 ? "No new receipts" : summary.text, ok: true)
    }
}

/// A short message that slides up over the bottom of a screen and leaves.
/// Deliberately the same shape as the undo toast, so the app has one way of
/// saying something quietly.
struct StatusToast: View {
    let note: RefreshNote

    var body: some View {
        Label(note.text, systemImage: note.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(note.ok ? Color.ink : Color.down)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Shows `note` near the bottom for a few seconds, then clears it.
    func refreshNote(_ note: Binding<RefreshNote?>, bottomPadding: CGFloat = 12) -> some View {
        overlay(alignment: .bottom) {
            if let value = note.wrappedValue {
                StatusToast(note: value)
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: value) {
                        // Long enough to read a sentence, short enough not to
                        // sit on top of the list.
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation(.snappy) { note.wrappedValue = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: note.wrappedValue)
        .sensoryFeedback(.success, trigger: note.wrappedValue) { _, new in new?.ok == true }
        .sensoryFeedback(.error, trigger: note.wrappedValue) { _, new in new?.ok == false }
    }
}

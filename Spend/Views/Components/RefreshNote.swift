import SwiftUI
import SwiftData

/// What a pull-to-refresh actually did.
///
/// Home and Activity both refresh exchange rates on pull-down; this gives that
/// gesture an answer, so the screen never looks exactly as it did before.
struct RefreshNote: Equatable {
    let text: String
    let ok: Bool

    /// Runs the whole refresh and says how it went.
    @MainActor
    static func run(in context: ModelContext) async -> RefreshNote {
        await FXService.ensureConverted(in: context)
        return RefreshNote(text: "Up to date", ok: true)
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
        .feedback(.confirm, trigger: note.wrappedValue) { _, new in new?.ok == true }
        .feedback(.fail, trigger: note.wrappedValue) { _, new in new?.ok == false }
    }
}

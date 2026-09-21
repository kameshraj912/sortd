import SwiftUI

/// The door behind the version number.
///
/// Five taps on Version in Settings opens this. It's for friends and
/// testers — a way to hand someone Pro without asking them to pay, and
/// without a server to do it with.
///
/// The tone here is deliberately looser than the rest of Sortd. Everything
/// else in the app is a money screen and money screens should be calm; this
/// one is a joke you had to work to find, so it's allowed to enjoy itself.
struct SecretCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var result: CompedPro.Result?
    @State private var shown: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Five taps. On a version number.")
                            .font(.headline)
                        Text("Either someone gave you a code, or you have a lot of time. Both are fine. Only one of them gets you Pro.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    TextField("Code", text: $code)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .onSubmit(redeem)
                    Button("Unlock", action: redeem)
                        .disabled(CompedPro.normalise(code).isEmpty)
                } footer: {
                    if let result {
                        Text(message(for: result))
                            .foregroundStyle(result.isSuccess ? Color.up : Color.down)
                    }
                }

                Section {
                    Text("Not a purchase, no subscription, nothing charged. Deleting all your data takes it back.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.page)
            .navigationTitle("Not a Settings Screen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func redeem() {
        let outcome = CompedPro.redeem(code)
        shown = switch outcome {
        case .unlocked: SortdVoice.proUnlocked
        case .alreadyUnlocked: SortdVoice.codeAlreadyUsed
        case .notACode: SortdVoice.notACode
        }
        withAnimation { result = outcome }
        if outcome.isSuccess {
            code = ""
            focused = false
        }
    }

    /// Held once it's shown, so a redraw doesn't reshuffle the joke
    /// mid-sentence.
    private func message(for result: CompedPro.Result) -> String {
        switch result {
        case .unlocked: shown ?? SortdVoice.proUnlocked
        case .alreadyUnlocked: shown ?? SortdVoice.codeAlreadyUsed
        case .notACode: shown ?? SortdVoice.notACode
        }
    }
}

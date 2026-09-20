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
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Well, look who reads the fine print.")
                            .font(.headline)
                        Text("Got a code? Put it in. If you don't, no judgement — you did just tap a version number five times.")
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
                    Text("A code unlocks Sortd Pro on this iPhone. It isn't a purchase, there's no subscription, and nothing is charged. Deleting all your data takes it away again.")
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
        withAnimation { result = outcome }
        if outcome.isSuccess {
            code = ""
            focused = false
        }
    }

    private func message(for result: CompedPro.Result) -> String {
        switch result {
        case .unlocked:
            "Pro unlocked. Go on then."
        case .alreadyUnlocked:
            "You already have it. Enthusiasm noted."
        case .notACode:
            "That's not it. Close, maybe. Probably not."
        }
    }
}

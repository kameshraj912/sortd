import SwiftUI
import UniformTypeIdentifiers

/// Shown instead of the app when the store on this iPhone cannot be opened
/// (`SpendStore.openFailure`). Calm and plain: what happened, what is safe,
/// and the ways back.
struct StoreRecoveryView: View {
    @State private var recovery = StoreRecovery()
    @State private var confirmingFresh = false
    @State private var pickingFile = false

    /// Why the store did not open. Only its type and code reach the support email.
    let failure: Error

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image("BrandIcon")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 15, style: .continuous))
                    .accessibilityHidden(true)
                    .padding(.top, 48)
                switch recovery.phase {
                case .choosing, .failed:
                    choices
                case .working:
                    ProgressView("Working…")
                        .padding(.top, 24)
                case .finished(let text):
                    finished(text)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color.page.ignoresSafeArea())
        .foregroundStyle(Color.ink)
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: Self.backupTypes) { result in
            Task { await recovery.restoreFromFile(result) }
        }
        .alert("Start fresh?", isPresented: $confirmingFresh) {
            Button("Start Fresh", role: .destructive) { recovery.startFresh() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sortd will start with no purchases. What is on this iPhone now will not come back unless you restore a backup instead.")
        }
    }

    private var choices: some View {
        VStack(spacing: 16) {
            Text("Sortd can't open your purchases")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Something went wrong with the data stored on this iPhone. Nothing has been deleted and nothing was sent anywhere. If you have a backup, you can bring your purchases back.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if case .failed(let why) = recovery.phase {
                Label(why, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Color.down)
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.card, in: .rect(cornerRadius: 16, style: .continuous))
            }
            VStack(spacing: 12) {
                #if SORTD_ICLOUD
                Button {
                    Task { await recovery.restoreFromICloud() }
                } label: {
                    Text("Restore from iCloud").primaryPill()
                }
                .primaryGlass()
                #endif
                Button { pickingFile = true } label: {
                    Label("Restore from a File", systemImage: "doc")
                        .frame(maxWidth: .infinity)
                }
                .secondaryGlass()
                Button(role: .destructive) { confirmingFresh = true } label: {
                    Label("Start Fresh", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .secondaryGlass()
                Link(destination: supportURL) {
                    Label("Contact Support", systemImage: "envelope")
                }
                .font(.subheadline)
                .padding(.top, 4)
            }
            .padding(.top, 8)
        }
    }

    private func finished(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.largeTitle)
                .foregroundStyle(Color.up)
                .accessibilityHidden(true)
            Text("All set")
                .font(.title2.weight(.semibold))
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
        .accessibilityElement(children: .combine)
    }

    /// A backup file, or the text of one.
    private static var backupTypes: [UTType] {
        [Backup.fileType, .json, .plainText]
    }

    /// An email to support that says what failed (the error's type, never
    /// any purchase).
    private var supportURL: URL {
        let type = String(reflecting: type(of: failure))
        let code = (failure as NSError).code
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = "support@sortd.page"
        parts.queryItems = [
            URLQueryItem(name: "subject", value: "Sortd can't open my purchases"),
            URLQueryItem(name: "body", value: "Sortd can't open my purchases on launch.\n\nWhat Sortd saw: \(type), code \(code).\n"),
        ]
        return parts.url ?? URL(string: "https://sortd.page/support")!
    }
}

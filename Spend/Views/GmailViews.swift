import SwiftUI
import SwiftData
import PostHog

/// Settings › Email Receipts: Gmail accounts connected with Google.
struct GmailSection: View {
    @Environment(\.modelContext) private var context
    @State private var accounts = GmailSync.accounts
    private let status = SyncStatus.gmail
    @State private var showingConnect = false
    @State private var disconnecting: GmailAccount?

    var body: some View {
        Section {
            ForEach(accounts) { account in
                Button { disconnecting = account } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "envelope.fill").foregroundStyle(Color.ink)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.email).foregroundStyle(Color.ink).lineLimit(1).truncationMode(.middle)
                                .postHogMask()
                            Text(status(account)).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                        Text("Disconnect").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .accessibilityHint("Disconnect this Gmail account")
            }
            Button { showingConnect = true } label: {
                Label(accounts.isEmpty ? "Connect Gmail" : "Connect Another Gmail", systemImage: "plus")
            }
            // Modifiers on a Section apply to every row inside it, so a
            // .sheet or .confirmationDialog attached to the Section itself
            // opens once per row: SwiftUI's second and third presentation
            // attempts fail and tear down the parent (Settings) sheet with
            // it. Anchored here, on this one row, which always exists
            // whether or not there are any accounts yet.
            .onChange(of: status.phase) { accounts = GmailSync.accounts }
            .sheet(isPresented: $showingConnect, onDismiss: { accounts = GmailSync.accounts }) { ConnectGmailSheet() }
            .confirmationDialog("Disconnect \(disconnecting?.email ?? "")?", isPresented: Binding(
                get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }), titleVisibility: .visible) {
                Button("Disconnect") { disconnect(deleting: false) }
                Button("Disconnect and Delete Purchases", role: .destructive) { disconnect(deleting: true) }
            } message: {
                Text("Sortd stops reading this Gmail and Google cancels its access. Purchases also logged by Apple Pay are kept either way.")
            }
            if !accounts.isEmpty {
                Button {
                    GmailSync.startSync(in: context)
                } label: {
                    HStack {
                        Text("Sync Now")
                        Spacer()
                        if status.isBusy { ProgressView() }
                    }
                }
                .disabled(status.isBusyForPerson)
                if status.isBusyForPerson || status.phase.isEnd {
                    SyncProgressCard(status: status) {
                        if case .failed(let f) = status.phase { GmailSync.retry(f, in: context) }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
        } header: {
            BoldHeader("Email Receipts")
        } footer: {
            Text("Finds receipts and bank alerts in your Gmail and reads them on this iPhone.")
        }
    }

    private func disconnect(deleting: Bool) {
        guard let account = disconnecting else { return }
        Task {
            await GmailSync.disconnect(account, deletePurchases: deleting, in: context)
            accounts = GmailSync.accounts
        }
        disconnecting = nil
    }

    /// The row's own line. While a connect or sync runs it is the live
    /// step ("Looking for receipts…"), so the row is useful the moment
    /// Google says yes; a first sync that stopped says so and the Retry
    /// card below takes it from there.
    private func status(_ a: GmailAccount) -> String {
        if status.isBusy, status.phase != .signingIn { return status.title }
        guard let last = a.lastSync else {
            if case .failed(let f) = status.phase { return f.message }
            return a.lastResult ?? "Not synced yet"
        }
        return "Synced \(last.formatted(.relative(presentation: .named))) · \(a.lastResult ?? "")"
    }
}

/// Explains exactly what Sortd reads before Google's sign-in opens
/// (App Store 5.1.1: ask for access only with a clear reason).
struct ConnectGmailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    /// Shared with Home and Settings: the connect keeps going if this closes.
    private let status = SyncStatus.gmail
    /// This sheet started (or is watching) a connect, so show its progress.
    @State private var watching = SyncStatus.gmail.isBusyForPerson
        || (SyncStatus.gmail.phase.isEnd && !SyncStatus.gmail.quiet)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "envelope.badge")
                        .font(.largeTitle)
                        .foregroundStyle(Color.ink)
                        .accessibilityHidden(true)
                    Text("Add purchases from your email")
                        .font(.title2.weight(.bold))
                    Text("Sortd finds receipts and bank alerts in your Gmail and adds them as purchases.")
                        .foregroundStyle(.secondary)
                    // Up top, where the eye already is, not under the explainer.
                    if showsProgress {
                        SyncProgressCard(status: status) { connect() }
                        if status.isBusy, status.phase != .signingIn {
                            Text("You can close this. Sortd keeps going and shows progress on Home.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        point("magnifyingglass", "Only receipts", "It searches for receipts and bank alerts. Other email is never opened.")
                        point("iphone", "Read on this iPhone", "Emails aren't copied to any server or shared.")
                        point("eye.slash", "Read-only", "Sortd can't send, delete or change your email.")
                        point("xmark.circle", "Stop any time", "Disconnect in Settings and Google cancels access.")
                    }
                    .padding(16)
                    .surface(radius: 16)
                    // Remove once Google's verification clears.
                    Text("Google may say Sortd isn't verified yet. That's expected while Google reviews it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .background(Color.page)
            .safeAreaInset(edge: .bottom) {
                Group {
                    if showsDone {
                        Button(action: primaryAction) {
                            Text(status.isBusy ? "Close" : "Done").primaryPill(enabled: true)
                        }
                        .primaryGlass()
                    } else {
                        // Google's own capsule already carries the branding;
                        // `.primaryGlass()` used to wrap it in a second, darker one.
                        Button(action: primaryAction) {
                            GoogleButtonLabel(working: status.phase == .signingIn)
                        }
                        .googleButton()
                    }
                }
                .disabled(status.phase == .signingIn)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .background(Color.page)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).frame(width: 22).foregroundStyle(Color.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Progress belongs to a connect this sheet is showing, not to the
    /// app's own quiet background sync.
    private var showsProgress: Bool {
        watching && status.phase != .idle
    }

    /// Past Google's sheet: the bottom button closes, the work carries on.
    private var showsDone: Bool {
        guard showsProgress else { return false }
        switch status.phase {
        case .connecting, .searching, .adding, .finished: return true
        default: return false
        }
    }

    private func primaryAction() {
        if showsDone { dismiss() } else { connect() }
    }

    private func connect() {
        watching = true
        GmailSync.startConnect(in: context)
    }
}

/// "Continue with Google", drawn to Google's sign-in branding rules, which the
/// OAuth review checks: the official G (cropped unchanged from Google's
/// asset pack), light theme white with a #747775 border and #1F1F1F text,
/// dark theme #131314 with #8E918F and #E3E3E3, 16 / 12 / 16 pt spacing.
/// Google's guidelines allow a rounded-rectangle shape (not only the full
/// pill); this uses `GoogleButtonLabel.cornerRadius` so it sits next to Sign
/// in with Apple as a matched pair, same height and corner radius. Draws its
/// own background and border: apply `.googleButton()`, not `.primaryGlass()`,
/// or the glass style wraps it in a second, darker capsule.
/// https://developers.google.com/identity/branding-guidelines
struct GoogleButtonLabel: View {
    var working = false
    @Environment(\.colorScheme) private var scheme

    /// Matches `SignInWithAppleButton`'s default corner radius, so the two
    /// sign-in buttons on the Account screen read as a pair.
    static let cornerRadius: CGFloat = 12

    var body: some View {
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        HStack(spacing: 12) {
            if working {
                ProgressView().frame(width: 20, height: 20)
            } else {
                Image("GoogleG").resizable().frame(width: 20, height: 20).accessibilityHidden(true)
            }
            Text(working ? "Opening Google…" : "Continue with Google")
                .font(.body.weight(.medium))
                .foregroundStyle(Color(hex: dark ? 0xE3E3E3 : 0x1F1F1F))
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(Color(hex: dark ? 0x131314 : 0xFFFFFF), in: shape)
        .overlay(shape.strokeBorder(Color(hex: dark ? 0x8E918F : 0x747775), lineWidth: 1))
        .contentShape(shape)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

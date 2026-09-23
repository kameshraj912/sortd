import SwiftUI
import SwiftData

/// Settings › Email Receipts: Gmail accounts connected with Google.
struct GmailSection: View {
    @Environment(\.modelContext) private var context
    @State private var accounts = GmailSync.accounts
    @State private var syncing = false
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
            if !accounts.isEmpty {
                Button {
                    Task {
                        syncing = true
                        await GmailSync.syncAll(in: context, force: true)
                        accounts = GmailSync.accounts
                        syncing = false
                    }
                } label: {
                    HStack {
                        Text("Sync Now")
                        Spacer()
                        if syncing { ProgressView() }
                    }
                }
                .disabled(syncing)
            }
        } header: {
            BoldHeader("Email Receipts")
        } footer: {
            Text("Finds receipts and bank alerts in your Gmail and reads them on this iPhone.")
        }
        .sheet(isPresented: $showingConnect, onDismiss: { accounts = GmailSync.accounts }) {
            if ProStore.shared.isPro { ConnectGmailSheet() } else { PaywallView(feature: .gmail) }
        }
        .confirmationDialog("Disconnect \(disconnecting?.email ?? "")?", isPresented: Binding(
            get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }), titleVisibility: .visible) {
            Button("Disconnect") { disconnect(deleting: false) }
            Button("Disconnect and Delete Purchases", role: .destructive) { disconnect(deleting: true) }
        } message: {
            Text("Sortd stops reading this Gmail and Google cancels its access. Purchases also logged by Apple Pay are kept either way.")
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

    private func status(_ a: GmailAccount) -> String {
        guard let last = a.lastSync else { return a.lastResult ?? "Not synced yet" }
        return "Synced \(last.formatted(.relative(presentation: .named))) · \(a.lastResult ?? "")"
    }
}

/// Explains exactly what Sortd reads before Google's sign-in opens
/// (App Store 5.1.1: ask for access only with a clear reason).
struct ConnectGmailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var working = false
    @State private var error: String?
    @State private var result: String?

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
                    VStack(alignment: .leading, spacing: 14) {
                        point("magnifyingglass", "Only receipts", "It searches for receipts and bank alerts. Other email is never opened.")
                        point("iphone", "Read on this iPhone", "Emails aren't copied to any server or shared.")
                        point("eye.slash", "Read-only", "Sortd can't send, delete or change your email.")
                        point("xmark.circle", "Stop any time", "Disconnect in Settings and Google cancels access.")
                    }
                    .padding(16)
                    .surface(radius: 16)
                    if let result {
                        Label(result, systemImage: "checkmark.circle.fill").foregroundStyle(Color.up)
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.down)
                    }
                    // Remove once Google's verification clears.
                    Text("Google may say Sortd isn't verified yet. That's expected while Google reviews it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .background(Color.page)
            .safeAreaInset(edge: .bottom) {
                Button(action: connect) {
                    if result == nil {
                        GoogleButtonLabel(working: working)
                    } else {
                        Text("Done").primaryPill(enabled: true)
                    }
                }
                .primaryGlass()
                .disabled(working)
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

    private func connect() {
        if result != nil { dismiss(); return }
        working = true
        error = nil
        Task {
            do {
                let s = try await GmailSync.connect(in: context)
                result = "Connected · \(s.text)"
            } catch GoogleAuth.AuthError.cancelled {
                // Closed the Google sheet: nothing to report.
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

/// "Continue with Google", drawn to Google's sign-in branding rules, which the
/// OAuth review checks: the official G (cropped unchanged from Google's
/// asset pack), light theme white with a #747775 border and #1F1F1F text,
/// dark theme #131314 with #8E918F and #E3E3E3, 16 / 12 / 16 pt spacing.
/// https://developers.google.com/identity/branding-guidelines
struct GoogleButtonLabel: View {
    var working = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        HStack(spacing: 12) {
            if working {
                ProgressView().frame(width: 20, height: 20)
            } else {
                Image("GoogleG").resizable().frame(width: 20, height: 20).accessibilityHidden(true)
            }
            Text(working ? "Connecting…" : "Continue with Google")
                .font(.body.weight(.medium))
                .foregroundStyle(Color(hex: dark ? 0xE3E3E3 : 0x1F1F1F))
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(Color(hex: dark ? 0x131314 : 0xFFFFFF), in: .capsule)
        .overlay(Capsule().strokeBorder(Color(hex: dark ? 0x8E918F : 0x747775), lineWidth: 1))
        .contentShape(.capsule)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

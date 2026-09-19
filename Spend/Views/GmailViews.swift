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
                            Text(account.email).foregroundStyle(Color.ink).lineLimit(1)
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
            Text("Finds bank alerts and receipts (food delivery, rides, app stores, online shops) in your Gmail and reads them on this iPhone.")
        }
        .sheet(isPresented: $showingConnect, onDismiss: { accounts = GmailSync.accounts }) {
            ConnectGmailSheet()
        }
        .confirmationDialog("Disconnect \(disconnecting?.email ?? "")?", isPresented: Binding(
            get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }), titleVisibility: .visible) {
            Button("Disconnect") { disconnect(deleting: false) }
            Button("Disconnect and Delete Its Purchases", role: .destructive) { disconnect(deleting: true) }
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
                        .font(.system(size: 40))
                        .foregroundStyle(Color.ink)
                        .accessibilityHidden(true)
                    Text("Add purchases from your email")
                        .font(.title2.weight(.bold))
                    Text("Sortd finds receipts and bank alerts in your Gmail — food delivery, rides, app stores, online shops — and adds them as purchases.")
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
                    Text("Google will show a warning that the app isn't verified yet while Sortd is being reviewed by Google.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .background(Color.page)
            .safeAreaInset(edge: .bottom) {
                Button(action: connect) {
                    HStack(spacing: 8) {
                        if working { ProgressView().tint(Color.onBrand) }
                        Text(working ? "Connecting…" : result == nil ? "Continue with Google" : "Done")
                    }
                    .primaryPill(enabled: !working)
                }
                .buttonStyle(.plain)
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
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
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

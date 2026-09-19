import SwiftUI
import SwiftData

/// Settings section: connected Gmail accounts, last sync, "Sync Now".
struct EmailSyncSection: View {
    @Environment(\.modelContext) private var context
    @State private var accounts = EmailSync.accounts
    @State private var syncing = false
    @State private var showingAdd = false
    @State private var lastSummary: String?

    var body: some View {
        Section {
            ForEach(accounts) { account in
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.label)
                    Text(status(account))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button("Remove", role: .destructive) {
                        EmailSync.remove(account)
                        accounts = EmailSync.accounts
                    }
                }
            }
            Button {
                showingAdd = true
            } label: {
                Label("Add Gmail Account", systemImage: "plus")
            }
            if !accounts.isEmpty {
                Button {
                    Task {
                        syncing = true
                        let s = await EmailSync.syncAll(in: context, force: true)
                        lastSummary = s.text
                        accounts = EmailSync.accounts
                        syncing = false
                    }
                } label: {
                    HStack {
                        Text("Sync Now")
                        Spacer()
                        if syncing { ProgressView() } else if let lastSummary {
                            Text(lastSummary).foregroundStyle(.secondary).font(.footnote)
                        }
                    }
                }
                .disabled(syncing)
            }
        } header: {
            BoldHeader("Apps Script Link (Older Way)")
        } footer: {
            Text("Connect Gmail above instead. This older link keeps working until you remove it.")
        }
        .sheet(isPresented: $showingAdd, onDismiss: { accounts = EmailSync.accounts }) {
            AddEmailAccountSheet()
        }
    }

    private func status(_ a: EmailAccount) -> String {
        guard let last = a.lastSync else { return a.lastResult ?? "Not synced yet" }
        return "\(last.formatted(.relative(presentation: .named))) · \(a.lastResult ?? "")"
    }
}

/// Paste the web-app URL and secret key from the Apps Script setup.
struct AddEmailAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var label = ""
    @State private var url = ""
    @State private var key = ""
    @State private var testing = false
    @State private var error: String?

    /// Pulls the script link out of whatever was pasted: copies from chat or
    /// notes often carry line breaks, spaces or invisible characters.
    private var parsedURL: URL? {
        let cleaned = url.filter { !$0.isWhitespace && $0.unicodeScalars.allSatisfy { $0.isASCII } }
        guard let range = cleaned.range(of: #"https://script\.google\.com/macros/s/[A-Za-z0-9_-]+/exec"#, options: .regularExpression),
              let u = URL(string: String(cleaned[range])) else { return nil }
        return u
    }

    /// The key is a UUID plus 8 hex characters. Finds it even if the pasted
    /// text includes a timestamp or "Info" from the Execution log.
    private var cleanKey: String {
        if let r = key.range(of: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12,}"#, options: .regularExpression) {
            return String(key[r])
        }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var missing: String? {
        if label.trimmingCharacters(in: .whitespaces).isEmpty { return "Add a name." }
        if parsedURL == nil { return url.isEmpty ? "Paste the web app link." : "That link doesn’t look like a script.google.com …/exec link." }
        if cleanKey.isEmpty { return "Paste the secret key." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Personal", text: $label)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    TextField("https://script.google.com/macros/s/…/exec", text: $url, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    SecureField("Secret key", text: $key)
                } header: {
                    BoldHeader("From the Apps Script setup")
                } footer: {
                    Text(missing ?? "The key is saved in this iPhone’s Keychain and is only sent to your own Google script.")
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.down)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.page)
            .navigationTitle("Gmail Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    if testing {
                        ProgressView()
                    } else {
                        Button("Save", systemImage: "checkmark", action: save)
                            .tint(Color.brand)
                            .disabled(missing != nil)
                            .opacity(missing == nil ? 1 : 0.3)
                    }
                }
            }
        }
    }

    /// Checks the URL and key work before saving, then runs a first sync.
    private func save() {
        guard let u = parsedURL else { return }
        testing = true
        error = nil
        Task {
            let probe = EmailAccount(label: label, url: u)
            let key = cleanKey
            Keychain.set(key, for: probe.keychainKey)
            do {
                _ = try await EmailSync.fetch(probe)
                Keychain.delete(probe.keychainKey)
                EmailSync.add(label: label, url: u, key: key)
                await EmailSync.syncAll(in: context, force: true)
                dismiss()
            } catch {
                Keychain.delete(probe.keychainKey)
                self.error = error.localizedDescription
            }
            testing = false
        }
    }
}

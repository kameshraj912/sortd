import SwiftUI
import SwiftData

/// Settings › Backup & Data: save or import a backup, export a CSV, or
/// delete everything Sortd has stored.
struct BackupDataSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var confirmingDelete = false
    @State private var csvFile: URL?
    @State private var backupFile: URL?

    var body: some View {
        List {
            ListPageTitle(title: "Backup & Data", subtitle: "Move your purchases, or clear them.")
            Section {
                if let file = backupFile {
                    ShareLink(item: file) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Save a Backup")
                                Text(lastBackupText)
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.down.document")
                        }
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        UserDefaults.standard.set(Date.now, forKey: Self.lastBackupKey)
                    })
                }
                NavigationLink {
                    ImportView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import")
                            Text("A statement, a screenshot, or a backup")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            } header: {
                BoldHeader("Backup")
            } footer: {
                Text("Everything stays on this iPhone. A backup is the only way to move phones, or to get your purchases back if you lose this one.")
            }

            Section {
                if let file = csvFile {
                    ShareLink(item: file) {
                        Label("Export Purchases (CSV)", systemImage: "square.and.arrow.up")
                    }
                }
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete All Data", systemImage: "trash")
                }
                .foregroundStyle(Color.down)
            } header: {
                BoldHeader("Your Data")
            } footer: {
                Text("Export gives you every purchase as a spreadsheet file. Delete removes everything Sortd has stored on this iPhone.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Backup & Data")
        .onAppear { refreshFiles() }
        .onChange(of: transactions.count) { _, _ in refreshFiles() }
        .confirmationDialog("Delete all data?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) {
                DataReset.deleteEverything(in: context)
            }
        } message: {
            Text("This removes every purchase, card, budget and setting from this iPhone. It can't be undone. Export first if you want a copy.")
        }
    }

    static let lastBackupKey = "lastBackupSaved"

    /// The share sheet needs a real file, so both are written when the
    /// screen opens and whenever the number of purchases changes.
    private func refreshFiles() {
        csvFile = transactions.isEmpty ? nil : CSVExport.file(transactions)
        backupFile = try? Backup.file(in: context)
    }

    private var lastBackupText: String {
        guard let last = UserDefaults.standard.object(forKey: Self.lastBackupKey) as? Date else {
            return "You haven't saved one yet"
        }
        return "Last saved \(last.formatted(.relative(presentation: .named)))"
    }
}

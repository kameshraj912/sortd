import SwiftUI
import SwiftData
import UIKit

/// Settings › Backup & Data: save or import a backup, export a CSV, or
/// delete everything Sortd has stored.
struct BackupDataSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var confirmingDelete = false
    /// Making the backup file takes a few seconds on a big history.
    @State private var preparing = false
    @State private var sharing: SharedFile?
    @State private var lastSaved = UserDefaults.standard.object(forKey: BackupDataSettingsView.lastBackupKey) as? Date
    @State private var failure: String?

    var body: some View {
        List {
            ListPageTitle(title: "Backup & Data")
            Section {
                Button(action: prepareBackup) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save a Backup")
                                .foregroundStyle(Color.primary)
                            // Redrawn each minute so "2 min ago" stays true.
                            TimelineView(.everyMinute) { context in
                                Text(preparing ? "Preparing your backup…" : Self.lastBackupText(lastSaved, now: context.date))
                            }
                            .font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: {
                        if preparing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.down.document")
                        }
                    }
                }
                .disabled(preparing)
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
                Text("Everything stays on this iPhone. Save a backup to move to a new phone, or in case you lose this one.")
            }

            Section {
                if !transactions.isEmpty {
                    ShareLink(item: CSVFileExport(), preview: SharePreview("Sortd purchases")) {
                        Label("Export as Spreadsheet", systemImage: "square.and.arrow.up")
                    }
                }
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete All Data", systemImage: "trash")
                }
                .foregroundStyle(Color.down)
            } header: {
                BoldHeader("Your Data")
            } footer: {
                // Only mention Export when the Export row is showing.
                Text(transactions.isEmpty
                     ? "Delete All Data removes everything Sortd has stored on this iPhone."
                     : "Export saves every purchase as a CSV spreadsheet.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Backup & Data")
        .sheet(item: $sharing) { file in
            ActivitySheet(items: [file.url]) { completed in
                // Only a finished share counts. Cancelling isn't a backup.
                if completed {
                    let now = Date.now
                    UserDefaults.standard.set(now, forKey: Self.lastBackupKey)
                    lastSaved = now
                }
                sharing = nil
            }
            // UIActivityViewController lays itself out. Forcing a medium
            // detent cropped its app row on an SE, and ignoring the safe
            // area let its bottom row sit under the home indicator.
        }
        .alert("Couldn't Save a Backup", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
        .confirmationDialog("Delete all data?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) {
                DataReset.deleteEverything(in: context)
                // Setup can't open over the Settings sheet: close it.
                Router.shared.settingsPath = []
                Router.shared.showingSettings = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(GmailSync.accounts.isEmpty
                 ? "Every purchase, card, budget and setting on this iPhone will be deleted. You can't undo this. Save a backup first if you want a copy."
                 : "Every purchase, card, budget and setting on this iPhone will be deleted, and Gmail disconnected. You can't undo this. Save a backup first if you want a copy.")
        }
    }

    nonisolated static let lastBackupKey = "lastBackupSaved"

    static func lastBackupText(_ last: Date?, now: Date = .now) -> String {
        guard let last else { return "Not saved yet" }
        if now.timeIntervalSince(last) < 60 { return "Last saved just now" }
        return "Last saved \(last.formatted(.relative(presentation: .named)))"
    }

    /// Reads the purchases (main thread), writes the file off it, then opens
    /// the share sheet. The spinner shows the whole time.
    private func prepareBackup() {
        guard !preparing else { return }
        preparing = true
        Task {
            // Let the spinner draw before the store is read.
            await Task.yield()
            do {
                let snapshot = try Backup.snapshot(in: context)
                let url = try await Task.detached(priority: .userInitiated) {
                    try Exports.write(try Backup.encode(snapshot),
                                      named: Exports.dated("Sortd backup", "sortdbackup"))
                }.value
                sharing = SharedFile(url: url)
            } catch {
                failure = error.localizedDescription
            }
            preparing = false
        }
    }
}

private struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The system share sheet, telling us whether the person actually saved or
/// sent the file (ShareLink doesn't say, so a cancel counted as a backup).
private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    let onFinish: (_ completed: Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            Task { @MainActor in onFinish(completed) }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

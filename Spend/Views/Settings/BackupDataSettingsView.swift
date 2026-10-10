import SwiftUI
import SwiftData
import UIKit

/// Settings › Backup & Data: back up to iCloud, save or import a backup
/// file, export a CSV, or delete everything Sortd has stored.
struct BackupDataSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var confirmingDelete = false
    /// Making the backup file takes a few seconds on a big history.
    @State private var preparing = false
    @State private var sharing: SharedFile?
    /// The spreadsheet is built when asked, which takes a few seconds on a
    /// long history; the row shows it is working until the share sheet opens.
    @State private var exporting = false
    @State private var sharingCSV: SharedFile?
    @State private var lastSaved = UserDefaults.standard.object(forKey: BackupDataSettingsView.lastBackupKey) as? Date
    @State private var failure: String?

    #if SORTD_ICLOUD
    @State private var cloud = CloudBackup.shared
    @State private var connectivity = Connectivity.shared
    @State private var confirmingSwitchOff = false
    @State private var confirmingRestore = false
    @State private var confirmingReplace = false
    @State private var cloudContents: Backup.Contents?
    @State private var replaceCount = 0
    @State private var restored: String?
    @State private var noBackup = false
    @State private var cloudFailure: String?
    /// Why the switch stayed off: no iCloud account, restricted, or not
    /// reachable. Shown under the switch until the next try.
    @State private var accountProblem: String?
    #endif

    var body: some View {
        List {
            ListPageTitle(title: "Backup & Data")
            #if SORTD_ICLOUD
            Section {
                Toggle(isOn: cloudSwitch) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Back up to iCloud")
                            // Redrawn each minute so "2 min ago" stays true.
                            TimelineView(.everyMinute) { tl in
                                let line = accountProblem
                                    ?? CloudBackup.statusLine(status: cloud.status, isEnabled: cloud.isEnabled,
                                                              isBehind: cloud.behind, isOnline: connectivity.isOnline)
                                Text(line ?? Self.lastCloudText(cloud.lastBackup, now: tl.date))
                                    .accessibilityLabel(line
                                                        ?? Self.lastCloudText(cloud.lastBackup, now: tl.date, spoken: true))
                            }
                            .font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: {
                        if cloud.status.isBusy {
                            ProgressView()
                        } else {
                            Image(systemName: "icloud")
                        }
                    }
                }
                if cloud.isEnabled {
                    Button(action: backUpToCloud) {
                        Label("Back Up Now", systemImage: "arrow.clockwise.icloud")
                    }
                    .disabled(cloud.status.isBusy)
                }
                Button { confirmingRestore = true } label: {
                    Label("Restore from iCloud", systemImage: "arrow.counterclockwise.icloud")
                }
                .disabled(cloud.status.isBusy)
            } header: {
                BoldHeader("iCloud")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Encrypted on this iPhone before it goes to iCloud.")
                    FooterLink("Learn more", destination: URL(string: "https://sortd.page/help#icloud-backup") ?? URL(fileURLWithPath: "/"))
                }
            }
            #endif

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
                BoldHeader("Backup File")
            } footer: {
                Text("A copy you keep yourself: in Files, on iCloud Drive, or a new phone.")
            }

            Section {
                if !transactions.isEmpty {
                    Button(action: prepareSpreadsheet) {
                        Label {
                            Text("Export as Spreadsheet")
                                .foregroundStyle(Color.primary)
                        } icon: {
                            if exporting {
                                ProgressView()
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                    .disabled(exporting)
                    .accessibilityValue(exporting ? "Preparing" : "")
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
        .sheet(item: $sharingCSV) { file in
            // Sharing a spreadsheet is not a backup, so it leaves "Last saved" alone.
            ActivitySheet(items: [file.url]) { _ in sharingCSV = nil }
        }
        .alert("Couldn't Save a Backup", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
        // Alerts, not confirmation dialogs, for everything below: a dialog
        // anchored to the row renders in a narrow popover that wrapped
        // three sentences into ragged lines (HANDOVER).
        #if SORTD_ICLOUD
        .alert("Delete the iCloud copy too?", isPresented: $confirmingSwitchOff) {
            Button("Delete iCloud Copy", role: .destructive) { deleteCloudCopy() }
            Button("Keep It", role: .cancel) {}
        } message: {
            Text("Backups have stopped either way. Keep the copy if you might want it on a new iPhone.")
        }
        .alert("Restore from iCloud?", isPresented: $confirmingRestore) {
            Button("Add What's Missing") { restore(.merge) }
            Button("Replace Everything", role: .destructive) { prepareReplace() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Add What's Missing keeps what's on this iPhone and adds what the backup has. Replace Everything clears this iPhone first.")
        }
        .alert(replaceTitle, isPresented: $confirmingReplace) {
            Button("Replace Everything", role: .destructive) { restore(.replace) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(replaceMessage)
        }
        .alert("Restored", isPresented: Binding(get: { restored != nil }, set: { if !$0 { restored = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restored ?? "")
        }
        .alert("No Backup in iCloud Yet", isPresented: $noBackup) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Turn on Back up to iCloud on the iPhone that has your purchases, then restore here.")
        }
        .alert("Couldn't Restore", isPresented: Binding(get: { cloudFailure != nil }, set: { if !$0 { cloudFailure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cloudFailure ?? "")
        }
        #endif
        .alert("Delete all data?", isPresented: $confirmingDelete) {
            Button("Delete Everything", role: .destructive) {
                DataReset.deleteEverything(in: context)
                // Setup can't open over the Settings sheet: close it.
                Router.shared.settingsPath = []
                Router.shared.showingSettings = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
    }

    nonisolated static let lastBackupKey = "lastBackupSaved"

    static func lastBackupText(_ last: Date?, now: Date = .now) -> String {
        guard let last else { return "Not saved yet" }
        if now.timeIntervalSince(last) < 60 { return "Last saved just now" }
        return "Last saved \(last.formatted(.relative(presentation: .named)))"
    }

    private var deleteMessage: String {
        #if SORTD_ICLOUD
        let deletesCloudCopy = cloud.deletesCloudCopyOnReset
        #else
        let deletesCloudCopy = false
        #endif
        return Self.deleteAllMessage(deletesCloudCopy: deletesCloudCopy)
    }

    /// The Delete All Data alert's message.
    nonisolated static func deleteAllMessage(deletesCloudCopy: Bool) -> String {
        var text = "Every purchase, card and budget on this iPhone goes."
        if deletesCloudCopy { text += " The iCloud backup is deleted too." }
        return text + " There's no undo."
    }

    // MARK: - Spreadsheet

    /// Builds the CSV (main thread, where the purchases live), writes the file
    /// off it, then opens the share sheet. The row's spinner shows meanwhile.
    private func prepareSpreadsheet() {
        guard !exporting else { return }
        exporting = true
        Task {
            // Let the spinner draw before the work starts.
            await Task.yield()
            let data = CSVExport.data(transactions)
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try Exports.write(data, named: Exports.dated("Sortd purchases", "csv"))
                }.value
                sharingCSV = SharedFile(url: url)
            } catch {
                failure = error.localizedDescription
            }
            exporting = false
        }
    }

    // MARK: - Backup file

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
                Analytics.shared.track(.backupCompleted)
            } catch {
                failure = error.localizedDescription
            }
            preparing = false
        }
    }
}

#if SORTD_ICLOUD
extension BackupDataSettingsView {
    /// "Last backup: 2 min ago". `spoken` uses full words for VoiceOver.
    static func lastCloudText(_ last: Date?, now: Date = .now, spoken: Bool = false) -> String {
        guard let last else { return "No backup yet" }
        if now.timeIntervalSince(last) < 60 { return "Last backup: just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = spoken ? .full : .abbreviated
        return "Last backup: \(formatter.localizedString(for: last, relativeTo: now))"
    }

    // MARK: - iCloud

    /// On: the first backup runs at once (unless there's nothing to back up,
    /// or iCloud already holds one to restore first). Off: backups stop, and
    /// the user chooses whether the copy stays.
    fileprivate var cloudSwitch: Binding<Bool> {
        Binding(get: { cloud.isEnabled }, set: { on in
            accountProblem = nil
            if on {
                // No iCloud account (or a restricted one): the switch stays
                // off and the line under it says why.
                Task {
                    if let reason = await CloudKitBackupStore.currentUnavailableReason() {
                        accountProblem = reason
                        AccessibilityNotification.Announcement(reason).post()
                        return
                    }
                    cloud.isEnabled = true
                    await cloud.backUpIfDue(from: context)
                }
            } else {
                cloud.isEnabled = false
                if cloud.lastBackup != nil || cloud.status == .paused(.restoreFirst) {
                    confirmingSwitchOff = true
                }
            }
        })
    }

    fileprivate func backUpToCloud() {
        Task {
            // The status line under the switch says what went wrong.
            try? await cloud.backUpNow(from: context)
        }
    }

    fileprivate func deleteCloudCopy() {
        Task {
            do { try await cloud.deleteCloudCopy() } catch { cloudFailure = error.localizedDescription }
        }
    }

    /// Replace needs to say what it will do, so it looks at the backup first.
    fileprivate func prepareReplace() {
        Task {
            do {
                guard let contents = try await cloud.contents() else {
                    noBackup = true
                    return
                }
                cloudContents = contents
                replaceCount = (try? context.fetchCount(FetchDescriptor<Transaction>())) ?? 0
                confirmingReplace = true
            } catch {
                cloudFailure = error.localizedDescription
            }
        }
    }

    fileprivate var replaceTitle: String {
        CloudBackup.replaceWarning(contents: cloudContents, purchasesHere: replaceCount).title
    }

    fileprivate var replaceMessage: String {
        CloudBackup.replaceWarning(contents: cloudContents, purchasesHere: replaceCount).message
    }

    fileprivate func restore(_ mode: Backup.Mode) {
        Task {
            do {
                // One download: nil means there was nothing to restore.
                guard let added = try await cloud.restoreIfPresent(into: context, mode: mode) else {
                    noBackup = true
                    return
                }
                Task { await FXService.backfill(in: context) }
                let badDates = cloud.lastRestoreBadDates
                if badDates > 0 {
                    restored = "\(added) purchase\(added == 1 ? "" : "s") added. \(Backup.badDatesNote(badDates))."
                } else {
                    restored = added == 0 ? "Nothing new to add. Everything in the backup is already here."
                        : "\(added) purchase\(added == 1 ? "" : "s") added."
                }
                AccessibilityNotification.Announcement(restored ?? "").post()
            } catch {
                cloudFailure = error.localizedDescription
            }
        }
    }
}
#endif

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

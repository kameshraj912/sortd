import SwiftUI
import SwiftData
import PhotosUI

/// Bring in a bank statement, or put a backup back.
///
/// One screen, one button. Pick a file or a photo and Sortd works out what
/// it is — a CSV export, a PDF statement, a screenshot of your bank app, or
/// a Sortd backup — rather than making you choose first.
///
/// Nothing saves until you have seen the list and tapped Add. Everything
/// goes through `TransactionLogger`, so a purchase already logged from an
/// Apple Pay tap is matched and merged, not doubled.
struct ImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var stage = Stage.start
    @State private var rows: [PickedRow] = []
    @State private var card = Card.other
    @State private var wasScanned = false
    /// Lines in the file the importer could not read. Shown, never hidden.
    @State private var skipped = 0
    @State private var error: String?
    /// The file was read but had no purchases in it. Changes the alert title.
    @State private var foundNothing = false
    @State private var busy = false
    /// Bumped on a finished import, for the haptic.
    @State private var imported = 0
    @State private var pickingFile = false
    @State private var photo: PhotosPickerItem?
    @State private var backup: Data?
    @State private var done: String?
    @State private var confirmingReplace = false
    /// Purchases on this phone now, and what the backup holds, for the
    /// Replace warning.
    @State private var replaceCount = 0
    @State private var backupContents: Backup.Contents?
    /// Purchases being added right now, for "Adding 42 purchases…".
    @State private var saving: Int?
    @State private var saveFailed = false

    private enum Stage { case start, review, backup }

    /// A found line plus whether the user wants it.
    private struct PickedRow: Identifiable {
        var row: StatementImport.Row
        var include: Bool
        var id: UUID { row.id }
    }

    var body: some View {
        List {
            ListPageTitle(title: "Import")
            switch stage {
            case .start: startSection
            case .review: reviewSections
            case .backup: backupSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Import")
        .saveFailedAlert($saveFailed)
        .feedback(.confirm, trigger: imported)
        .fileImporter(isPresented: $pickingFile,
                      allowedContentTypes: StatementReader.readableTypes) { result in
            switch result {
            case .success(let url): load { try await StatementReader.read(fileAt: url) }
            case .failure(let e): error = e.localizedDescription
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            load {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw StatementReader.Failure.unreadable
                }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("statement-\(UUID().uuidString).png")
                try data.write(to: url)
                defer { try? FileManager.default.removeItem(at: url) }
                return try await StatementReader.read(fileAt: url)
            }
        }
        .alert(foundNothing ? "No Purchases Found" : "Couldn't Import",
               isPresented: Binding(get: { error != nil },
                                    set: { if !$0 { error = nil; foundNothing = false } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
        .alert("Done", isPresented: Binding(get: { done != nil }, set: { if !$0 { done = nil } })) {
            Button("OK") { dismiss() }
        } message: {
            Text(done ?? "")
        }
        // An alert, like Delete All Data: the message names counts and a date,
        // which is too much for the narrow popover a dialog renders in.
        .alert(replaceTitle, isPresented: $confirmingReplace) {
            Button("Replace Everything", role: .destructive) { restore(.replace) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(replaceMessage)
        }
    }

    // MARK: - Pick something

    @ViewBuilder private var startSection: some View {
        Section {
            Button { pickingFile = true } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Choose a File")
                        Text("A CSV or PDF statement, or a Sortd backup")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "folder")
                }
            }
            PhotosPicker(selection: $photo, matching: .images) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Choose a Screenshot")
                        Text("A picture of your bank app's list")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "photo")
                }
            }
        } footer: {
            Text("Read on this iPhone. Nothing uploads, and nothing saves until you tap Add.")
        }

        if busy {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Reading your statement…").foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Check before saving

    @ViewBuilder private var reviewSections: some View {
        Section {
            Picker(selection: $card) {
                ForEach(Card.mine) { c in Text(c.name).tag(c) }
                Text("Card not known").tag(Card.other)
            } label: {
                Label("Paid With", systemImage: "creditcard")
            }
        } footer: {
            Text("Statements don't always say which card.")
        }

        if wasScanned {
            Section {
                Label("Read from a picture. Check the amounts.", systemImage: "eye")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }

        let spend = rows.filter { $0.row.kind == .spend }
        let moneyIn = rows.filter { $0.row.kind == .moneyIn }

        Section {
            if spend.isEmpty {
                Text("No purchases found.").foregroundStyle(.secondary)
            }
            ForEach($rows) { $picked in
                if picked.row.kind == .spend { line($picked) }
            }
        } header: {
            BoldHeader("Purchases (\(spend.filter(\.include).count) of \(spend.count))")
        } footer: {
            if let note = StatementImport.skippedNote(skipped) {
                Text(note)
            }
        }

        if !moneyIn.isEmpty {
            Section {
                ForEach(moneyIn) { picked in
                    HStack {
                        Text(picked.row.detail).lineLimit(1)
                        Spacer()
                        Text(Money.format(picked.row.amount, picked.row.currency ?? Money.home))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
            } header: {
                BoldHeader("Money In — Not Added")
            } footer: {
                Text("Money in isn't spending, so it's left out of your totals.")
            }
        }

        Section {
            Button {
                save(spend.filter(\.include).map(\.row))
            } label: {
                HStack {
                    if let saving {
                        Text("Adding \(saving) purchase\(saving == 1 ? "" : "s")…")
                    } else {
                        Text("Add \(spend.filter(\.include).count) Purchase\(spend.filter(\.include).count == 1 ? "" : "s")")
                    }
                    Spacer()
                    if busy { ProgressView() }
                }
            }
            .disabled(busy || spend.filter(\.include).isEmpty)

            Button("Start Again") { reset() }
                .foregroundStyle(.secondary)
        } footer: {
            Text("Purchases Sortd already has won't be added twice.")
        }
    }

    private func line(_ picked: Binding<PickedRow>) -> some View {
        Button {
            picked.wrappedValue.include.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: picked.wrappedValue.include ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(picked.wrappedValue.include ? Color.ink : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(picked.wrappedValue.row.detail)
                        .foregroundStyle(Color.ink).lineLimit(1)
                    Text(picked.wrappedValue.row.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Money.format(picked.wrappedValue.row.amount,
                                  picked.wrappedValue.row.currency ?? Money.home))
                    .monospacedDigit()
                    .foregroundStyle(Color.ink)
            }
        }
        .accessibilityLabel("\(picked.wrappedValue.row.detail), \(Money.spoken(picked.wrappedValue.row.amount, picked.wrappedValue.row.currency ?? Money.home)) on \(picked.wrappedValue.row.date.formatted(date: .abbreviated, time: .omitted))")
        .accessibilityValue(picked.wrappedValue.include ? "Will be added" : "Skipped")
    }

    // MARK: - A backup instead

    @ViewBuilder private var backupSection: some View {
        Section {
            Label("That's a Sortd backup, not a statement.", systemImage: "arrow.counterclockwise")
        } header: {
            BoldHeader("Restore")
        }
        Section {
            Button("Add What's Missing") { restore(.merge) }
            Button("Replace Everything", role: .destructive) {
                replaceCount = (try? context.fetchCount(FetchDescriptor<Transaction>())) ?? 0
                backupContents = backup.flatMap(Backup.contents(of:))
                confirmingReplace = true
            }
            .foregroundStyle(Color.down)
            Button("Cancel") { reset() }.foregroundStyle(.secondary)
        } footer: {
            Text("Add What's Missing keeps what's on this iPhone. Replace Everything clears it first. Use that on a new phone.")
        }
    }

    private var replaceTitle: String {
        guard let backupContents else { return "Replace this iPhone's data with this backup?" }
        return Backup.replaceWarning(backup: backupContents, purchasesHere: replaceCount).title
    }

    private var replaceMessage: String {
        guard let backupContents else { return "Everything on this iPhone will be replaced. This can't be undone." }
        return Backup.replaceWarning(backup: backupContents, purchasesHere: replaceCount).message
    }

    // MARK: - Work

    /// Reads whatever was picked, then decides: statement or backup.
    private func load(_ work: @escaping () async throws -> StatementReader.Reading) {
        busy = true
        error = nil
        foundNothing = false
        AccessibilityNotification.Announcement("Reading your statement").post()
        Task {
            do {
                let reading = try await Perf.measure("statement.read") { try await work() }
                if StatementReader.looksLikeBackup(reading.text) {
                    backup = Data(reading.text.utf8)
                    stage = .backup
                } else {
                    let parsed = reading.wasScanned || !looksLikeCSV(reading.text)
                        ? StatementImport.parse(text: reading.text)
                        : StatementImport.parse(csv: reading.text)
                    let found = parsed.rows
                    guard !found.isEmpty else {
                        foundNothing = true
                        error = [StatementImport.skippedNote(parsed.skipped), SortdVoice.importFoundNothing]
                            .compactMap { $0 }.joined(separator: " ")
                        busy = false
                        photo = nil
                        return
                    }
                    skipped = parsed.skipped
                    rows = found.map { PickedRow(row: $0, include: $0.kind == .spend) }
                    wasScanned = reading.wasScanned
                    card = Card.mine.first ?? .other
                    stage = .review
                }
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
            photo = nil
        }
    }

    /// A CSV has the same number of separators on most lines. Text pulled
    /// out of a PDF does not.
    private func looksLikeCSV(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline).prefix(10)
        guard lines.count >= 2 else { return false }
        let counts = lines.map { line in
            max(line.filter { $0 == "," }.count,
                max(line.filter { $0 == ";" }.count, line.filter { $0 == "\t" }.count))
        }
        guard let first = counts.first, first >= 2 else { return false }
        return counts.filter { $0 == first }.count >= counts.count - 1
    }

    private func reset() {
        rows = []
        skipped = 0
        backup = nil
        wasScanned = false
        photo = nil
        stage = .start
    }

    /// Both of these write into the main SwiftData context, so the work
    /// itself has to stay on the main actor. Pausing a moment first lets the
    /// spinner draw — before, `busy` went true and false inside one runloop
    /// turn, so a big statement looked like the app had frozen.
    private func save(_ found: [StatementImport.Row]) {
        guard !busy else { return }
        busy = true
        saving = found.count
        Analytics.shared.track(.statementImported, ["rows": .int(found.count)])
        Task {
            // Let "Adding N purchases…" reach the screen before the work starts.
            try? await Task.sleep(for: .milliseconds(30))
            WidgetBridge.hold()
            let (added, merged, saved) = StatementImport.saveChecked(found, card: card, in: context)
            do { try TransactionLogger.refreshUncategorised(in: context) } catch {
                ErrorLog.report(error, where: "ImportView.refreshUncategorised")
            }
            // Refreshes the widget once for the whole import.
            WidgetBridge.release()
            Task { await FXService.backfill(in: context) }
            busy = false
            saving = nil
            guard saved else {
                // "Done" would be false: say the write failed instead.
                saveFailed = true
                return
            }
            imported += 1
            done = merged > 0
                ? "\(added) added. \(merged) \(merged == 1 ? "was" : "were") already in Sortd."
                : "\(added) added."
            AccessibilityNotification.Announcement(done ?? "").post()
        }
    }

    private func restore(_ mode: Backup.Mode) {
        guard let data = backup, !busy else { return }
        busy = true
        Task {
            await Task.yield()
            do {
                let result = try Backup.restore(data, mode: mode, into: context)
                Task { await FXService.backfill(in: context) }
                imported += 1
                done = result.summary
                Analytics.shared.track(.restoreCompleted, ["mode": .string(String(describing: mode))])
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}

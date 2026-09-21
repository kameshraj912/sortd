import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Files handed to the share sheet: the backup and the CSV.
///
/// Nothing is written until the user actually shares. The copy then goes into
/// a private folder with complete file protection (unreadable while the iPhone
/// is locked), and is removed the next time Sortd starts, Settings opens, or
/// Delete All runs. So no full copy of the data sits around in plain files.
enum Exports {
    nonisolated static var folder: URL {
        FileManager.default.temporaryDirectory.appending(path: "Exports", directoryHint: .isDirectory)
    }

    nonisolated static func write(_ data: Data, named name: String) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true,
                               attributes: [.protectionKey: FileProtectionType.complete])
        let url = folder.appending(path: name)
        try? fm.removeItem(at: url)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Removes shared copies, plus any backup or CSV that older builds left
    /// loose in the temporary folder.
    nonisolated static func clear() {
        let fm = FileManager.default
        try? fm.removeItem(at: folder)
        for f in (try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil)) ?? []
        where ["csv", "sortdbackup"].contains(f.pathExtension) {
            try? fm.removeItem(at: f)
        }
    }

    nonisolated static func dated(_ stem: String, _ ext: String) -> String {
        "\(stem) \(Date.now.formatted(.iso8601.year().month().day())).\(ext)"
    }
}

/// The backup, built from the live store only when the user shares it.
nonisolated struct BackupExport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { _ in
            let data = try await MainActor.run { try Backup.data(in: SpendStore.container.mainContext) }
            return SentTransferredFile(try Exports.write(data, named: Exports.dated("Sortd backup", "sortdbackup")))
        }
    }
}

/// Every purchase as a CSV, built only when the user shares it.
nonisolated struct CSVFileExport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { _ in
            let data = try await MainActor.run {
                let all = try SpendStore.container.mainContext.fetch(FetchDescriptor<Transaction>())
                return CSVExport.data(all)
            }
            return SentTransferredFile(try Exports.write(data, named: Exports.dated("Sortd purchases", "csv")))
        }
    }
}

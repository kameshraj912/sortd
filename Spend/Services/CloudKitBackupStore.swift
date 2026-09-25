import Foundation
import CloudKit

/// The backup blob as one record, `Backup/main`, in the user's private
/// CloudKit database. Storage counts against the user's iCloud quota, not
/// ours, and we cannot read the private database. The blob is a `CKAsset`
/// because a field is capped at 1 MB and a long history is bigger.
@MainActor
final class CloudKitBackupStore: CloudBackupStore {
    static let recordType = "Backup"
    static let recordName = "main"
    static let blobField = "blob"
    static let modifiedField = "modified"

    /// Made on first use, not at launch: `CKContainer.default()` needs the
    /// iCloud entitlement and the app must open fine without it.
    private lazy var database = CKContainer.default().privateCloudDatabase
    private var recordID: CKRecord.ID { CKRecord.ID(recordName: Self.recordName) }

    func save(_ blob: Data, modified: Date) async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "sortd-cloud-backup-\(UUID().uuidString).bin")
        try blob.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record[Self.blobField] = CKAsset(fileURL: url)
        record[Self.modifiedField] = modified
        do {
            // allKeys: the whole record is ours; no fetch first, no conflict.
            let results = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            if let outcome = results.saveResults[recordID] { _ = try outcome.get() }
        } catch {
            throw Self.map(error)
        }
    }

    func fetch() async throws -> (blob: Data, modified: Date)? {
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch {
            throw Self.map(error)
        }
        guard let asset = record[Self.blobField] as? CKAsset, let file = asset.fileURL,
              let blob = try? Data(contentsOf: file) else {
            throw CloudBackupError.corrupt
        }
        let modified = record[Self.modifiedField] as? Date ?? record.modificationDate ?? .distantPast
        return (blob, modified)
    }

    func delete() async throws {
        do {
            _ = try await database.deleteRecord(withID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone.
        } catch {
            throw Self.map(error)
        }
    }

    /// CloudKit's errors as the few Sortd shows. Anything else passes through
    /// and lands in `.failed` with its own words.
    nonisolated static func map(_ error: Error) -> Error {
        guard let ck = error as? CKError else { return error }
        switch ck.code {
        case .quotaExceeded:
            return CloudBackupError.quotaExceeded
        case .requestRateLimited, .serviceUnavailable, .zoneBusy:
            return CloudBackupError.rateLimited(retryAfter: ck.retryAfterSeconds ?? 30)
        case .notAuthenticated:
            return CloudBackupError.notSignedIn
        case .partialFailure:
            // Our one record's own error is inside.
            if let inner = ck.partialErrorsByItemID?.values.first { return map(inner) }
            return error
        default:
            return error
        }
    }
}

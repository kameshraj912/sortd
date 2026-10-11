import Foundation
import CloudKit
import MachO

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

    /// Whether this build may touch CloudKit. Without the iCloud entitlement
    /// (a simulator or free-team build) `CKContainer.default()` aborts the
    /// app, so every call checks this first and fails with `Unavailable`
    /// instead. Tests pass false.
    private let entitled: Bool
    /// The iCloud account the last `accountID` saw; cleared when iOS says
    /// the account changed.
    private var cachedAccount: String?
    private var watchingAccount = false

    init(entitled: Bool = CloudKitBackupStore.hasICloudEntitlement) {
        self.entitled = entitled
    }

    /// Made on first use, not at launch, and only with the entitlement.
    private var container: CKContainer {
        get throws {
            guard entitled else { throw Unavailable() }
            return CKContainer.default()
        }
    }
    private var database: CKDatabase {
        get throws { try container.privateCloudDatabase }
    }
    private var recordID: CKRecord.ID { CKRecord.ID(recordName: Self.recordName) }

    /// No iCloud in this copy of Sortd (no entitlement): said plainly, and
    /// never sent as a fault.
    struct Unavailable: LocalizedError, Equatable {
        var errorDescription: String? { "iCloud isn't available in this copy of Sortd." }
    }

    /// The signed-in iCloud account, as CloudKit's user record name for this
    /// container. Nil when unknown (no entitlement, no account, offline).
    func accountID() async -> String? {
        guard let container = try? self.container else { return nil }
        if !watchingAccount {
            watchingAccount = true
            NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cachedAccount = nil }
            }
        }
        if let cachedAccount { return cachedAccount }
        let id = try? await container.userRecordID().recordName
        cachedAccount = id
        return id
    }

    func save(_ blob: Data, modified: Date) async throws {
        let database = try self.database
        let url = FileManager.default.temporaryDirectory
            .appending(path: "sortd-cloud-backup-\(UUID().uuidString).bin")
        // Off the main thread: a long history is a few megabytes.
        try await Task.detached(priority: .utility) { try blob.write(to: url, options: .atomic) }.value
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
        let database = try self.database
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
        let database = try self.database
        do {
            _ = try await database.deleteRecord(withID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone.
        } catch {
            throw Self.map(error)
        }
    }

    /// Why the switch can't go on, in one plain line; nil when iCloud is
    /// ready. Checked before the switch turns on, so a phone with no iCloud
    /// account says so instead of leaving the switch to flip back unexplained.
    nonisolated static func unavailableReason(for status: CKAccountStatus) -> String? {
        switch status {
        case .available:
            nil
        case .noAccount:
            "Sign in to iCloud in the Settings app to back up."
        case .restricted:
            "iCloud is turned off for this iPhone by a restriction."
        case .couldNotDetermine, .temporarilyUnavailable:
            "Couldn't check iCloud. Try again in a moment."
        @unknown default:
            "Couldn't check iCloud. Try again in a moment."
        }
    }

    /// Asks the system for the account state now (not at launch: like the
    /// database, the container is only touched on use).
    static func currentUnavailableReason() async -> String? {
        guard hasICloudEntitlement else { return Unavailable().errorDescription }
        do {
            return unavailableReason(for: try await CKContainer.default().accountStatus())
        } catch {
            return unavailableReason(for: .couldNotDetermine)
        }
    }

    /// CloudKit's errors as the few Sortd acts on. Anything else becomes a
    /// `Failure` with plain words for the status line, never CloudKit's own.
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
            return Failure(code: ck.code)
        default:
            return Failure(code: ck.code)
        }
    }

    /// A CloudKit problem Sortd has no special handling for, said plainly.
    struct Failure: LocalizedError {
        let code: CKError.Code
        var errorDescription: String? {
            switch code {
            case .networkUnavailable, .networkFailure:
                "iCloud couldn't be reached. Check the connection; Sortd will try again."
            case .accountTemporarilyUnavailable:
                "iCloud isn't available right now. Sortd will try again."
            default:
                "iCloud had a problem (code \(code.rawValue)). Sortd will try again later."
            }
        }
    }
}

// MARK: - Entitlement

extension CloudKitBackupStore {
    /// Whether the running app was signed with iCloud (CloudKit). Read once
    /// from the main executable: the `__TEXT,__entitlements` section on the
    /// simulator, the code signature's entitlements blob on a device. A
    /// simulator build with neither has no iCloud; on a device, a signature
    /// that can't be read counts as having it, as every phone build does.
    nonisolated static let hasICloudEntitlement: Bool = {
        if let text = embeddedEntitlements() { return text.contains("com.apple.developer.icloud-services") }
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }()

    private nonisolated static func embeddedEntitlements() -> String? {
        guard let header = _dyld_get_image_header(0) else { return nil }
        let mh = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
        guard mh.pointee.magic == MH_MAGIC_64 else { return nil }
        var size: UInt = 0
        if let bytes = getsectiondata(mh, "__TEXT", "__entitlements", &size), size > 0 {
            return String(decoding: UnsafeRawBufferPointer(start: bytes, count: Int(size)), as: UTF8.self)
        }
        // The code signature, inside __LINKEDIT, which dyld keeps mapped.
        var command = UnsafeRawPointer(mh).advanced(by: MemoryLayout<mach_header_64>.size)
        var linkedit: (vmaddr: UInt64, fileoff: UInt64)?
        var signature: (offset: UInt32, size: UInt32)?
        for _ in 0..<mh.pointee.ncmds {
            let load = command.load(as: load_command.self)
            if load.cmd == UInt32(LC_SEGMENT_64) {
                let segment = command.load(as: segment_command_64.self)
                let name = withUnsafeBytes(of: segment.segname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
                if name == "__LINKEDIT" { linkedit = (segment.vmaddr, segment.fileoff) }
            } else if load.cmd == UInt32(LC_CODE_SIGNATURE) {
                let data = command.load(as: linkedit_data_command.self)
                signature = (data.dataoff, data.datasize)
            }
            command = command.advanced(by: Int(load.cmdsize))
        }
        guard let linkedit, let signature, UInt64(signature.offset) >= linkedit.fileoff else { return nil }
        let slide = _dyld_get_image_vmaddr_slide(0)
        let address = Int(slide) + Int(linkedit.vmaddr) + Int(UInt64(signature.offset) - linkedit.fileoff)
        guard let blob = UnsafeRawPointer(bitPattern: address) else { return nil }
        func word(_ offset: Int) -> UInt32 { blob.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian }
        // SuperBlob: magic, length, count, then (type, offset) pairs.
        guard word(0) == 0xfade0cc0 else { return nil }
        let count = Int(word(8))
        guard count < 64 else { return nil }
        for i in 0..<count {
            let offset = Int(word(12 + i * 8 + 4))
            guard offset + 8 <= Int(signature.size) else { continue }
            // The XML entitlements blob: magic, length, then the plist.
            guard word(offset) == 0xfade7171 else { continue }
            let length = Int(word(offset + 4))
            guard length > 8, offset + length <= Int(signature.size) else { return nil }
            return String(decoding: UnsafeRawBufferPointer(start: blob.advanced(by: offset + 8), count: length - 8),
                          as: UTF8.self)
        }
        return nil
    }
}

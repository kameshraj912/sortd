import Foundation
import CryptoKit
import Security

/// The backup key as a synchronizable Keychain item, so iCloud Keychain
/// (end-to-end encrypted by Apple) carries it to the user's next phone.
///
/// Its own service, apart from `Keychain` (the Gmail keys): those are
/// this-device-only and `Keychain.deleteAll()` wipes them on Delete All
/// Data, while this key must survive that (the next backup reuses it, and
/// another phone may need it).
@MainActor
final class KeychainBackupKeyStore: BackupKeyStore {
    static let service = "com.kameshraj.spend.backup-key"
    static let account = "main"

    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Couldn't reach the Keychain (\(status))."
        }
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            // Needed on every call, or a synchronizable item is invisible.
            kSecAttrSynchronizable as String: true,
        ]
    }

    func load() throws -> SymmetricKey? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        switch status {
        case errSecSuccess:
            // Anything but a 256-bit key can't open the backup: say so, rather
            // than looking like "no key yet" (which could lead to a new one).
            guard let data = out as? Data, data.count == 32 else { throw CloudBackupError.corrupt }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw Failure(status: status)
        }
    }

    func save(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        // Not ThisDeviceOnly: that would stop it syncing.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}

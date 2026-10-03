import Foundation
import Security

/// A Keychain call that did not return success, for `ErrorLog`.
nonisolated struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Keychain status \(status)" }
}

/// Tiny wrapper for secrets (the Google sign-in token that Delete Account
/// cancels). Stored only on this device.
enum Keychain {
    private static let service = "com.kameshraj.spend"

    /// In a test run the real Keychain is not open to the unsigned test host
    /// (every write fails with a missing entitlement), so the items live in
    /// memory there, as a scratch copy of the real thing. Nil in the app.
    private static var memory: [String: String]? =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ? [:] : nil

    static func set(_ value: String, for account: String) {
        if memory != nil { memory?[account] = value; return }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess {
            ErrorLog.report(KeychainError(status: status), where: "Keychain.set")
        }
    }

    static func get(_ account: String) -> String? {
        if let memory { return memory[account] }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Every item Sortd stored, including ones from an earlier install.
    static func deleteAll() {
        if memory != nil { memory = [:]; return }
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }

    /// Every stored account name that starts with `prefix`.
    static func accounts(withPrefix prefix: String) -> [String] {
        if let memory { return memory.keys.filter { $0.hasPrefix(prefix) }.sorted() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let items = out as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }.filter { $0.hasPrefix(prefix) }
    }

    static func delete(_ account: String) {
        if memory != nil { memory?[account] = nil; return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

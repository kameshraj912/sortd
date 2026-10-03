import Foundation

/// Gmail receipts were removed on 2 Oct 2026 (Google only approves the
/// `gmail.readonly` scope after a paid yearly security assessment). This runs
/// once, at launch, so a phone that had Gmail connected ends clean: the saved
/// Google refresh tokens go (after Google is asked to cancel them), and so do
/// the settings that only the Gmail feature used.
///
/// Purchases that came from email stay. `TxnSource.email`, `ImportedRecord`,
/// `seenIn` and the other stored fields are unchanged on purpose, so old rows
/// still load, show and back up.
enum GmailCleanup {
    static let doneKey = "gmailCleanupDone"

    /// Settings only the removed Gmail feature (and what it fed) used.
    static let defaultsKeys = [
        "gmailAccounts",     // the connected accounts
        "emailAccounts",     // the older Apps Script link
        "pendingRefunds",    // refund emails waiting for their purchase
        "pendingCardDigits", // "Which card?" queue
    ]

    /// Keychain names the Gmail feature used: `google-refresh-<email>` for
    /// each account, `email-sync-<id>` for the Apps Script link.
    static let keychainPrefixes = ["google-refresh-", "email-sync-"]

    /// Deletes the old tokens and settings. Returns the refresh tokens it
    /// found, so the caller can ask Google to cancel them. Safe to call
    /// again; the second call finds nothing.
    @discardableResult
    static func run(defaults: UserDefaults = .standard,
                    tokens: KeychainTokens = .live) -> [String] {
        var found: [String] = []
        for prefix in keychainPrefixes {
            for account in tokens.accounts(prefix) {
                if prefix == "google-refresh-", let token = tokens.get(account) {
                    // On the revoke list before the item goes: the list keeps
                    // it until Google confirms, so an app closed mid-request
                    // does not leave the grant on for good.
                    GoogleAuth.addPending(token)
                    found.append(token)
                }
                tokens.delete(account)
            }
        }
        for key in defaultsKeys { defaults.removeObject(forKey: key) }
        defaults.set(true, forKey: doneKey)
        return found
    }

    /// Once per install: runs `run`, then cancels the grants with Google.
    static func runOnce(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        let found = run(defaults: defaults)
        guard !found.isEmpty else { return }
        Task { await GoogleAuth.revokeLegacy(found) }
    }

    /// The Keychain, as far as the clean-up needs it, so a test can swap it.
    struct KeychainTokens {
        var accounts: (_ prefix: String) -> [String]
        var get: (_ account: String) -> String?
        var delete: (_ account: String) -> Void

        static let live = KeychainTokens(accounts: { Keychain.accounts(withPrefix: $0) },
                                         get: { Keychain.get($0) },
                                         delete: { Keychain.delete($0) })
    }
}

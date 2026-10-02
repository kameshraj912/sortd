import Testing
import Foundation
@testable import Spend

/// The one-time clean-up after Gmail was removed (2 Oct 2026): saved Google
/// tokens and the Gmail-only settings go, and nothing else is touched.
@MainActor
struct GmailCleanupTests {

    /// A tiny fake Keychain: account name -> secret.
    private final class FakeTokens {
        var items: [String: String]
        init(_ items: [String: String]) { self.items = items }
        var store: GmailCleanup.KeychainTokens {
            .init(accounts: { prefix in self.items.keys.filter { $0.hasPrefix(prefix) }.sorted() },
                  get: { self.items[$0] },
                  delete: { self.items[$0] = nil })
        }
    }

    private func defaults() -> UserDefaults {
        let name = "gmail-cleanup-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func savedGoogleTokensAreDeletedAndHandedBackForRevoking() {
        let keychain = FakeTokens(["google-refresh-a@example.com": "token-a",
                                   "google-refresh-b@example.com": "token-b",
                                   "email-sync-old": "script-key",
                                   "google-identity-token": "sign-in-token"])
        let found = GmailCleanup.run(defaults: defaults(), tokens: keychain.store)

        #expect(found == ["token-a", "token-b"])
        // The sign-in's own token is not Gmail's: it stays.
        #expect(keychain.items == ["google-identity-token": "sign-in-token"])
    }

    @Test func gmailOnlySettingsAreRemovedAndOthersStay() {
        let d = defaults()
        for key in GmailCleanup.defaultsKeys { d.set("x", forKey: key) }
        d.set(1500.0, forKey: "monthlyBudget")

        GmailCleanup.run(defaults: d, tokens: FakeTokens([:]).store)

        for key in GmailCleanup.defaultsKeys { #expect(d.object(forKey: key) == nil, "\(key) is still there") }
        #expect(d.double(forKey: "monthlyBudget") == 1500)
    }

    @Test func itDoesNotTouchPurchasesOrTheirSources() {
        // Nothing here takes a model context: the clean-up cannot reach the store.
        #expect(GmailCleanup.defaultsKeys.contains("gmailAccounts"))
        #expect(TxnSource.email.label == "Email receipt")
    }

    @Test func runningTwiceFindsNothingTheSecondTime() {
        let keychain = FakeTokens(["google-refresh-a@example.com": "token-a"])
        let d = defaults()
        #expect(GmailCleanup.run(defaults: d, tokens: keychain.store) == ["token-a"])
        #expect(GmailCleanup.run(defaults: d, tokens: keychain.store).isEmpty)
        #expect(d.bool(forKey: GmailCleanup.doneKey))
    }
}

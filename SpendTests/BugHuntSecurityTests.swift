import Testing
import Foundation
import SwiftData
@testable import Spend

// Bug hunt 3 Oct 2026, area security-masvs (docs/testing/attacks.md).
// Each test was written to fail on the code of that day. All five are fixed
// (docs/BugHunt-2026-10-03-fixes-c.md) and run in the normal suite.

// MARK: - Fakes for the account store (this file's own)

@MainActor
private final class SecHuntKeychain: AccountKeychain {
    var stored: Account?
    func load() throws -> Account? { stored }
    func save(_ account: Account) throws { stored = account }
    func delete() throws { stored = nil }
}

/// `revoke` throws `revokeError` when set (Apple's sheet cancelled is
/// `.cancelled`); `deletePerson` always works and counts.
@MainActor
private final class SecHuntRevoker: AccountRevoker {
    var revokeError: AccountError?
    var personDeletes = 0
    func revoke(_ account: Account) async throws {
        if let revokeError { throw revokeError }
    }
    func deletePerson(hash: String) async throws { personDeletes += 1 }
}

@MainActor
private final class SecHuntSink: IdentitySink {
    func identify(_ hash: String) {}
    func reset() {}
}

@MainActor
private final class SecHuntChecker: CredentialStateChecker {
    func isRevoked(_ account: Account) async -> Bool { false }
}

@MainActor
private final class SecHuntProvider: IdentityProvider {
    let account: Account
    init(_ account: Account) { self.account = account }
    func signIn() async throws -> Account { account }
}

/// A stand-in Keychain for `GmailCleanup.run`.
private final class SecHuntTokenBox {
    var items: [String: String] = [:]
}

@MainActor
struct BugHuntSecurityTests {
    let context: ModelContext

    init() throws {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    private func freshDefaults(_ name: String) -> UserDefaults {
        let suite = "sec-hunt-\(name)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    // MARK: sec-01

    /// Cancelling Apple's "sign in once more to confirm" sheet during Delete
    /// Account still deletes the usage record and signs out (and, from
    /// "Delete Account and All Data", the view then wipes every purchase).
    @Test func cancellingApplesConfirmSheetCancelsTheDelete() async throws {
        let account = Account(provider: .apple, subject: "001234.sechunt", email: nil)
        let revoker = SecHuntRevoker()
        let store = AccountStore(keychain: SecHuntKeychain(), revoker: revoker, sink: SecHuntSink(),
                                 checker: SecHuntChecker(), defaults: freshDefaults(#function), salt: "sec-hunt")
        try await store.signIn(with: SecHuntProvider(account))

        // The user taps Cancel on Apple's sheet (AppleIdentityProvider.error(from:) -> .cancelled).
        revoker.revokeError = .cancelled
        _ = await store.deleteAccount()

        #expect(store.current == account, "a cancelled confirmation signed the user out anyway")
        #expect(revoker.personDeletes == 0, "the usage record was deleted after the user cancelled")
    }

    // MARK: sec-02

    /// The Bills widget draws each bill's name (the shop, from
    /// `WidgetBridge`'s `Bill(name: $0.merchant ...)`) through `MoneyRow`,
    /// which never applies `.shopNameIsPrivate()`. With "Show Amounts When
    /// Locked" on, the whole widget is `.privacySensitive(false)`, so shop
    /// names show on a locked phone (StandBy), against the widget rule.
    @Test func billsWidgetKeepsShopNamesPrivateWhileLocked() throws {
        let bridge = try source("Spend/Services/WidgetBridge.swift")
        #expect(bridge.contains("WidgetSummary.Bill(name: $0.merchant"), "premise: a bill's name is the shop")

        let widget = try source("SortdWidget/SortdWidget.swift")
        let start = try #require(widget.range(of: "struct BillsView"))
        let end = try #require(widget.range(of: "struct SortdBillsWidget", range: start.upperBound..<widget.endIndex))
        let bills = String(widget[start.upperBound..<end.lowerBound])
        #expect(bills.contains("ShopName(") || bills.contains(".shopNameIsPrivate()"),
                "BillsView draws bill.name without the always-private shop name rule")
    }

    // MARK: sec-03

    /// The Gmail clean-up deletes each old Google refresh token before
    /// Google has confirmed the revoke, and keeps it nowhere else; the
    /// revoke then runs in an unawaited Task (60 s default timeout). If the
    /// app is closed in that window the token is gone and the Gmail grant
    /// is never cancelled (`doneKey` is already set, so it never re-runs).
    @Test func gmailCleanupKeepsTheTokenUntilGoogleConfirms() throws {
        let token = "sec-hunt-refresh-\(UUID().uuidString)"
        let box = SecHuntTokenBox()
        box.items["google-refresh-raj@example.com"] = token
        let tokens = GmailCleanup.KeychainTokens(
            accounts: { prefix in box.items.keys.filter { $0.hasPrefix(prefix) } },
            get: { box.items[$0] },
            delete: { box.items[$0] = nil })

        let found = GmailCleanup.run(defaults: freshDefaults(#function), tokens: tokens)
        #expect(found == [token])

        let pending = GoogleAuth.pendingTokens(Keychain.get("google-revoke-pending"))
        #expect(box.items.values.contains(token) || pending.contains(token),
                "the refresh token was deleted before any revoke was attempted, and is kept nowhere")
    }

    // MARK: sec-04

    /// Secrets.xcconfig.example says to leave ACCOUNT_WORKER_URL empty until
    /// the Worker is deployed, but it ships a live-looking URL, and unlike
    /// the Sentry and PostHog placeholders ("replace_me") the app accepts
    /// it: a copied example sends Delete Account calls to
    /// sortd-account.example.workers.dev, a host Sortd does not own.
    @Test func exampleWorkerURLIsNeverUsedAsARealWorker() throws {
        let example = try source("Secrets.xcconfig.example")
        let line = try #require(example.split(separator: "\n").first { $0.hasPrefix("ACCOUNT_WORKER_URL") })
        let value = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            .last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let store = try source("Spend/Services/AccountStore.swift")
        #expect(value.isEmpty || store.contains("example.workers.dev"),
                "example value \(value) would be read by WorkerRevoker.fromBundle as a real Worker")
    }

    // MARK: sec-05

    /// Every Apple Pay run keeps the raw shop, amount and card text in
    /// UserDefaults ("lastTapReceived" and the last 10 "recentTapRuns"),
    /// and it stays there after the purchase is deleted. attacks.md
    /// STORAGE-1: only the SwiftData store may hold a shop name.
    /// Fixed: the run log keeps only how each field arrived (empty, a
    /// placeholder, a length), never the words.
    @Test func aDeletedTapLeavesNoShopOrAmountInDefaults() async throws {
        let shop = "ZEBRACAFE\(UUID().uuidString.prefix(6))"
        let now = Date(timeIntervalSince1970: 1_790_000_000)

        // The exact line `recordReach` stores for a Wallet run.
        let line = LogWalletTapIntent.record(transaction: nil, amount: "A$12.34", merchant: shop,
                                             card: "NAB Visa Debit", notification: WalletNotification(), at: now)
        #expect(!line.contains(shop), "the stored run line holds the shop name")
        #expect(!line.contains("12.34"), "the stored run line holds the amount")

        // Through the real path: log, then delete the purchase.
        let book = CardBook(defaults: UserDefaults(suiteName: "sec-hunt-card-\(UUID().uuidString)")!)
        let r = try await LogPurchaseIntent.handle(merchant: shop, amount: "A$12.34", card: "NAB Visa Debit",
                                                   in: context, book: book, now: now)
        let t = try #require(r.transaction)
        context.delete(t)
        try context.save()
        let kept = LogPurchaseIntent.recentRuns() + [LogPurchaseIntent.reachDefaults.string(forKey: LogPurchaseIntent.lastTapKey) ?? ""]
        #expect(!kept.contains { $0.contains(shop) }, "the deleted purchase's shop is still in UserDefaults")
    }
}

// MARK: - Bug hunt 8 Oct 2026, area security-masvs

/// Hunt of 8 Oct 2026 (branch hunt-20261008). Each case fails on the code of
/// that day and is tagged `.knownBug`, so CI stays green until the fix lands.
/// sec-1008-2 and sec-1008-3 read the source, because the fix needs a call
/// (a flush, an App Lock check) that does not exist yet.
@MainActor
struct BugHuntSecurityHunt2Tests {
    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: sec-1008-1

    /// The Release build (the one sent to TestFlight) is compiled with
    /// SORTD_REPLAY (27281e4, 6 Oct), and `Analytics.replayAllowed` turns
    /// PostHog session replay on for a TestFlight receipt
    /// (docs/AppStoreChecklist.md: "TestFlight builds record"). The privacy
    /// page, updated 8 Oct, still says "Sortd doesn't record your screen.
    /// That's true of the TestFlight beta and the App Store version." Every
    /// beta tester with usage data on is recorded against a page that says
    /// they are not.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "sec-1008-1", "TestFlight builds record the screen; the privacy page says they never do"))
    func theBetaDoesNotRecordWhileThePrivacyPageSaysItNeverDoes() throws {
        let project = try source("Spend.xcodeproj/project.pbxproj")
        // The Release line has no DEBUG; Debug's does.
        let releaseRecords = project.split(separator: "\n").contains { line in
            line.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS") && line.contains("SORTD_REPLAY") && !line.contains("DEBUG")
        }
        #expect(Analytics.replayAllowed(flagOn: true, isTestFlight: true), "premise: a TestFlight copy with the flag records")
        let privacy = try source("site/privacy.html")
        let promisesNoRecording = privacy.contains("Sortd doesn't record your screen. That's true of the TestFlight beta")
        #expect(!(releaseRecords && promisesNoRecording),
                "Release (TestFlight) is built with SORTD_REPLAY, yet site/privacy.html says the beta never records the screen")
    }

    // MARK: sec-1008-2

    /// Delete Account (and Delete All Data while signed in) resets PostHog and
    /// has the Worker delete the person (`bulk_delete`, events included), but
    /// never flushes the SDK first. PostHog's `reset()` (posthog-ios, this
    /// build) does not clear its queue, so the events captured under the
    /// signed-in hash in the last 30 s (flush interval) or last 20 events
    /// ("Application Opened", `tab_opened`) are uploaded after the delete,
    /// and with `personProfiles = .always` PostHog makes the person again.
    /// Steps: Google account, open Sortd, Settings › Account › Delete Account
    /// within 30 s. Not run against the live PostHog project.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "sec-1008-2", "events queued under the deleted hash are sent after Delete Account and recreate the PostHog person"))
    func deleteAccountSendsQueuedEventsBeforeThePersonIsDeleted() throws {
        let store = try source("Spend/Services/AccountStore.swift")
        let analytics = try source("Spend/Services/Analytics.swift")
        #expect(analytics.contains("personProfiles = .always"), "premise: every event makes a person")
        #expect(store.contains("deletePerson(hash: hash)"), "premise: Delete Account deletes the person")
        #expect(store.lowercased().contains("flush") || analytics.lowercased().contains("flush"),
                "nothing flushes PostHog's queue before the person delete, so queued events recreate the person")
    }

    // MARK: sec-1008-3

    /// App Lock ("Unlock Sortd to see your spending") covers only the app's
    /// window. The Siri questions in `SpendQuestionIntents.swift` use
    /// `.requiresAuthentication`, which only needs the iPhone unlocked: with
    /// App Lock on, "Hey Siri, last purchase in Sortd" on someone else's
    /// unlocked phone answers "A$5.50 at Seven Seeds" with no Face ID.
    /// iOS's own "Require Face ID" (which Settings suggests next to it)
    /// hides the app from Siri. Expected words are Raj's call; this pins
    /// "no value while locked".
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "sec-1008-3", "Siri questions answer with shop and amount while App Lock is on"))
    func siriQuestionsRespectAppLock() throws {
        let intents = try source("Spend/Intents/SpendQuestionIntents.swift")
        #expect(intents.contains("LastPurchaseIntent"), "premise: the question intents live here")
        #expect(intents.contains("AppLock") || intents.contains("appLockEnabled"),
                "no question intent looks at App Lock before answering")
    }

    // MARK: sec-1008-4

    /// The "Paid to" shop field in New Purchase and in a purchase's detail
    /// leaves autocorrect on, so the iOS keyboard learns shop names and
    /// offers them in other apps (MASTG-TEST-0055, attacks.md STORAGE-2
    /// "keyboard cache"). It also "corrects" real shop names (ZEBRACAFE).
    /// The quick-entry field and Activity's search already use
    /// `.autocorrectionDisabled()`.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug(id: "sec-1008-4", "the shop field feeds the keyboard's learned words"))
    func theShopFieldDoesNotFeedTheKeyboardDictionary() throws {
        for path in ["Spend/Views/AddTransactionView.swift", "Spend/Views/TransactionDetailView.swift"] {
            let text = try source(path)
            let field = try #require(text.range(of: "TextField(\"Paid to\""), "\(path): no Paid to field")
            // The modifiers right after the field, up to the next view.
            let tail = String(text[field.upperBound...].prefix(600))
            let modifiers = tail.range(of: "LabeledContent").map { String(tail[..<$0.lowerBound]) } ?? tail
            #expect(modifiers.contains(".autocorrectionDisabled()"),
                    "\(path): the shop field autocorrects, so the keyboard learns shop names")
        }
    }
}

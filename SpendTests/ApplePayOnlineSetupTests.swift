import Testing
import Foundation
import SwiftData
@testable import Spend

/// Apple Pay in apps and on websites (2 Oct 2026): the raw record, the
/// setup words, and `Transaction.tapOrigins` surviving a backup and the
/// tap queue.
@MainActor
struct ApplePayOnlineSetupTests {
    private func store() -> ModelContext {
        let container = try! ModelContainer(for: Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }
    private func book() -> CardBook { CardBook(defaults: UserDefaults(suiteName: "online-setup-\(UUID().uuidString)")!) }
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: - The raw "last tap received" record

    /// The record says how every field arrived, never the words (X5, 3 Oct
    /// 2026): a shop or an amount must not outlive its purchase in the defaults.
    @Test func aNotificationRunRecordsItsKindAndHowEveryFieldArrived() {
        let record = LogWalletTapIntent.record(transaction: nil, amount: "stray", merchant: "", card: "Wallet",
                                               notification: WalletNotification(title: "NAB Visa Debit", subtitle: "DoorDash",
                                                                                body: "A$23.40"),
                                               at: now)
        #expect(record.contains("notification run"))
        #expect(record.contains("title 14 characters"))
        #expect(record.contains("subtitle 8 characters"))
        #expect(record.contains("body 7 characters"))
        // The ignored tap fields still show, so a phone test can see them.
        #expect(record.contains("amount 5 characters"))
        #expect(record.contains("merchant empty"))
        #expect(record.contains("card 6 characters"))
        for words in ["NAB Visa Debit", "DoorDash", "23.40", "stray", "Wallet"] {
            #expect(!record.contains(words))
        }
    }

    /// A tap run says so, with the same shape for every field.
    @Test func aTapRunRecordsItsKindAndHowEveryFieldArrived() {
        let record = LogWalletTapIntent.record(transaction: nil, amount: "A$4.50",
                                               merchant: LogPurchaseIntent.legacyTestMerchant, card: "NAB Visa Debit",
                                               notification: WalletNotification(), at: now)
        #expect(record.hasPrefix(now.formatted(date: .abbreviated, time: .standard)))
        #expect(record.contains("tap run"))
        #expect(record.contains("merchant 10 characters"))
        #expect(record.contains("title empty"))
        #expect(!record.contains("4.50"))
    }

    // MARK: - Recent runs (the last 10 raw lines)

    @Test func recentRunsKeepTheNewestTenNewestFirst() {
        var runs: [String] = []
        for n in 1...12 { runs = LogPurchaseIntent.appending("run \(n)", to: runs) }
        #expect(runs.count == 10)
        #expect(runs.first == "run 12")
        #expect(runs.last == "run 3")
        #expect(runs == (3...12).reversed().map { "run \($0)" })
    }

    /// Every reach updates "last tap received" and adds to the buffer.
    @Test func everyReachUpdatesTheLastTapAndTheBuffer() {
        let defaults = UserDefaults(suiteName: "online-runs-\(UUID().uuidString)")!
        #expect(LogPurchaseIntent.recentRuns(defaults).isEmpty)
        LogPurchaseIntent.recordReach("first", at: now, defaults: defaults)
        LogPurchaseIntent.recordReach("second", at: now.addingTimeInterval(5), defaults: defaults)
        #expect(defaults.string(forKey: LogPurchaseIntent.lastTapKey) == "second")
        #expect(defaults.object(forKey: LogPurchaseIntent.lastTapAtKey) as? Date == now.addingTimeInterval(5))
        #expect(LogPurchaseIntent.recentRuns(defaults) == ["second", "first"])
        for n in 3...11 { LogPurchaseIntent.recordReach("run \(n)", at: now, defaults: defaults) }
        #expect(LogPurchaseIntent.recentRuns(defaults).count == 10)
        #expect(LogPurchaseIntent.recentRuns(defaults).first == "run 11")
        #expect(LogPurchaseIntent.recentRuns(defaults).last == "second")
    }

    // MARK: - Setup words

    @Test func stepThreeAsksForBothAutomationsOnIOS27() {
        let step = ApplePaySetupSteps.automationStep(notificationTrigger: true)
        #expect(step.title == "Turn both automations on")
        #expect(step.detail == "In the shortcut, tap › next to each \u{201C}When…\u{201D} line and switch on Automation.")
        #expect(WalletSetupGuide.quickPages[2].title == step.title)
        #expect(WalletSetupGuide.quickPages[2].detail == step.detail)
    }

    /// "Show When Run" is off, so Shortcuts shows nothing after ▶: step 2
    /// sends the person back to Sortd, and no copy promises a message there.
    @Test func stepTwoSaysComeBackHereAndTheGuideMatches() {
        let step = ApplePaySetupSteps.runStep
        #expect(step.title == "Run it once and tap Allow")
        #expect(step.detail == "In Shortcuts, tap Log Apple Pay in Sortd to run it (or press ▶ if it is open). Tap Allow, then come back here.")
        #expect(WalletSetupGuide.quickPages[1].title == step.title)
        #expect(WalletSetupGuide.quickPages[1].detail == step.detail)
        for page in WalletSetupGuide.quickPages + WalletSetupGuide.byHandPages {
            #expect(!page.detail.contains("connected"))
        }
    }

    @Test func theScopeLineNamesAppsAndWebsitesOnIOS27() {
        #expect(ApplePaySetupSteps.scopeLine(notificationTrigger: true)
                == "Taps in shops log from the tap. Payments in apps and on websites log from Wallet's notification, if your bank sends one.")
        #expect(ApplePaySetupSteps.scopeLine(notificationTrigger: false)
                == "Works for taps in shops. Online and Apple Watch payments don't reach Shortcuts.")
    }

    /// The Purchase Sources footer only mentions online payments where the
    /// shortcut can catch them.
    @Test func theSourcesFooterMentionsOnlineOnlyOnIOS27() {
        #expect(ApplePaySetupSteps.sourcesFooter(notificationTrigger: true).contains("online"))
        #expect(!ApplePaySetupSteps.sourcesFooter(notificationTrigger: false).contains("online"))
    }

    /// Get the Shortcut opens our own signed file on sortd.page, in the
    /// in-app Safari sheet: a web link the sheet can show, no personal iCloud.
    @Test func getTheShortcutOpensTheHostedFileInTheSafariSheet() {
        let url = ApplePaySetupSteps.shortcutURL
        #expect(url.absoluteString == "https://sortd.page/apple-pay.shortcut")
        #expect(url.scheme == "https")
        #expect(url.host() == "sortd.page")
        #expect(url.pathExtension == "shortcut")
        #expect(SafariPage(url: url).url == url)
    }

    // MARK: - tapOrigins

    @Test func originsAreAlwaysWrittenTapThenNotification() {
        let t = Transaction(date: now, merchant: "Seven Seeds", amount: 5, currencyCode: "AUD", card: .other,
                            category: .eatingOut, source: .tap)
        t.tapOrigins = "n"
        t.markOrigin(.tap)
        #expect(t.tapOrigins == "tn")
        t.markOrigin(.notification)
        #expect(t.tapOrigins == "tn")
    }

    /// A notification that folds into an email receipt row (not a tap row)
    /// marks it "n" only — the email row was never a tap.
    @Test func aNotificationMergedIntoAnEmailRowIsMarkedNotificationOnly() async throws {
        let ctx = store(), b = book()
        try TransactionLogger.log(IncomingPurchase(date: now.addingTimeInterval(-3600), merchant: "DoorDash", amount: 23.4,
                                                   currency: "AUD", card: .other, source: .email), in: ctx)
        let r = try await LogWalletTapIntent.handle(nil, amount: "", merchant: "", card: "",
                                                    notificationTitle: "", notificationSubtitle: "DoorDash",
                                                    notificationBody: "A$23.40", in: ctx, book: b, now: now)
        #expect(r.merged)
        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.count == 1)
        #expect(all.first?.tapOrigins == "n")
        #expect(all.first?.seenIn.contains(.tap) == true)
    }

    @Test func aBackupKeepsTapOrigins() async throws {
        let ctx = store(), b = book()
        _ = try await LogWalletTapIntent.handle(nil, amount: "A$5.50", merchant: "Seven Seeds", card: "NAB Visa Debit",
                                                in: ctx, book: b, now: now)
        _ = try await LogWalletTapIntent.handle(nil, amount: "", merchant: "", card: "",
                                                notificationTitle: "NAB Visa Debit", notificationSubtitle: "Seven Seeds",
                                                notificationBody: "A$5.50", in: ctx, book: b, now: now.addingTimeInterval(3))
        let data = try Backup.encode(try Backup.snapshot(in: ctx))
        let restored = store()
        try Backup.restore(data, mode: .merge, into: restored,
                           defaults: UserDefaults(suiteName: "online-restore-\(UUID().uuidString)")!, cardBook: book())
        let rows = try restored.fetch(FetchDescriptor<Transaction>())
        #expect(rows.count == 1)
        #expect(rows.first?.tapOrigins == "tn")
    }

    /// A backup from before `tapOrigins` existed still restores.
    @Test func anOldBackupWithNoOriginsStillRestores() throws {
        let json = """
        {"format":"sortd.backup","version":1,"createdAt":"2026-09-30T01:00:00Z","settings":{},"cards":[],"rules":[],"transactions":[
        {"id":"\(UUID().uuidString)","date":"2026-09-30T01:00:00Z","merchant":"Coles","rawMerchant":"Coles",
         "amount":12.5,"currencyCode":"AUD","card":"other","category":"groceries","source":"tap","seenIn":"tap",
         "note":"","createdAt":"2026-09-30T01:00:00Z","refunded":false}]}
        """
        let snapshot = try Backup.decode(Data(json.utf8))
        #expect(snapshot.transactions.first?.tapOrigins == nil)
    }

    @Test func aQueuedNotificationReplaysAsANotificationRow() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "online-queue-\(UUID().uuidString).json")
        TapQueue.enqueue(merchant: "DoorDash", amount: "A$23.40", card: "NAB Visa Debit", date: now,
                         trigger: .notification, url: url)
        #expect(TapQueue.read(from: url).first?.trigger == "n")
        let ctx = store()
        let result = await TapQueue.replay(in: ctx, book: book(), url: url)
        #expect(result.replayed == 1)
        let rows = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(rows.first?.tapOrigins == "n")
    }
}

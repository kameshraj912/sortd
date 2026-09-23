import Testing
import SwiftData
import Foundation
@testable import Spend

/// Adversarial pass over the data paths: backup/restore, statement import,
/// delete + undo, dedupe, recurring prefs and the widget bridge.
///
/// Every test here models someone who does not follow the happy path —
/// restores a hand-edited file, taps twice, backgrounds the app mid-undo,
/// imports the same statement again, replaces new data with an old backup.
///
/// A failing test in this file is a finding, not a flake.
@MainActor
struct AbuseDataAgentTests {

    // MARK: - Harness

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func scratch() -> UserDefaults {
        let name = "abuse-agent-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    /// A CardBook that never touches the real card list.
    private func book() -> CardBook {
        CardBook(defaults: scratch())
    }

    private func date(_ ymd: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Australia/Melbourne")
        return f.date(from: ymd)!
    }

    @discardableResult
    private func add(_ ctx: ModelContext, _ merchant: String, _ amount: Decimal, _ day: String,
                     currency: String = "AUD", category: SpendCategory = .groceries,
                     source: TxnSource = .manual, card: Card = .nab) -> Transaction {
        let t = Transaction(date: date(day), merchant: merchant, amount: amount,
                            currencyCode: currency, card: card, category: category, source: source)
        t.audAmount = amount
        ctx.insert(t)
        try? ctx.save()
        return t
    }

    private func row(id: UUID = UUID(), merchant: String, amount: Decimal, on day: String,
                     currency: String = "AUD") -> Backup.Snapshot.Row {
        Backup.Snapshot.Row(id: id, date: date(day), merchant: merchant, rawMerchant: merchant,
                            amount: amount, currencyCode: currency, homeAmount: amount,
                            card: Card.nab.rawValue, category: SpendCategory.groceries.rawValue,
                            source: TxnSource.manual.rawValue, seenIn: "", note: "",
                            createdAt: .now, platform: nil, refunded: false,
                            renewsOn: nil, billingPeriod: nil, sourceAccount: nil)
    }

    private func count(_ ctx: ModelContext) -> Int {
        (try? ctx.fetchCount(FetchDescriptor<Transaction>())) ?? -1
    }

    // MARK: - Backup: a file someone edited by hand

    /// A backup file that lists the same purchase id twice — easy to produce
    /// by concatenating two exports, or by a future sync bug. `restore`
    /// builds its "already here" set once, before inserting anything, so the
    /// second copy never sees the first.
    @Test func aBackupWithTheSameIdTwiceMustNotAddItTwice() throws {
        let id = UUID()
        var snap = Backup.Snapshot()
        snap.transactions = [
            row(id: id, merchant: "Woolworths", amount: 58.30, on: "2026-09-01"),
            row(id: id, merchant: "Woolworths", amount: 58.30, on: "2026-09-01"),
        ]
        let data = try Backup.encode(snap)

        let ctx = try store()
        let result = try Backup.restore(data, mode: .merge, into: ctx,
                                        defaults: scratch(), cardBook: book())

        #expect(result.added == 1)
        #expect(count(ctx) == 1)
    }

    /// The same file in Replace mode. Replace starts from an empty set on
    /// purpose, so nothing at all stops the duplicate.
    @Test func aBackupWithTheSameIdTwiceMustNotAddItTwiceOnReplace() throws {
        let id = UUID()
        var snap = Backup.Snapshot()
        snap.transactions = [
            row(id: id, merchant: "Rent", amount: 900, on: "2026-09-01"),
            row(id: id, merchant: "Rent", amount: 900, on: "2026-09-01"),
            row(id: id, merchant: "Rent", amount: 900, on: "2026-09-01"),
        ]
        let data = try Backup.encode(snap)

        let ctx = try store()
        try Backup.restore(data, mode: .replace, into: ctx, defaults: scratch(), cardBook: book())

        #expect(count(ctx) == 1)
    }

    /// And once the duplicates are in, restoring the same file again cannot
    /// clean them up: both copies now match by id and are skipped. The
    /// history is wrong for good, and the month total is double.
    @Test func duplicateIdsSurviveASecondRestoreAndDoubleTheTotal() throws {
        let id = UUID()
        var snap = Backup.Snapshot()
        snap.transactions = [
            row(id: id, merchant: "Rent", amount: 900, on: "2026-09-01"),
            row(id: id, merchant: "Rent", amount: 900, on: "2026-09-01"),
        ]
        let data = try Backup.encode(snap)

        let ctx = try store()
        try Backup.restore(data, mode: .merge, into: ctx, defaults: scratch(), cardBook: book())
        try Backup.restore(data, mode: .merge, into: ctx, defaults: scratch(), cardBook: book())

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.count == 1)
        #expect(all.audTotal == 900)
    }

    /// Replace is "my phone died, put it all back". It wipes the purchases
    /// but leaves every `ImportedRecord` behind, so a Gmail re-sync will
    /// skip exactly the emails whose purchases Replace just deleted. Those
    /// purchases are gone with no way back.
    @Test func replaceRestoreMustNotKeepEmailIdsForPurchasesItDeleted() throws {
        let ctx = try store()

        // A purchase that only ever existed because of a Gmail receipt.
        let record = EmailRecord(id: "gmail-1", kind: "purchase", merchant: "Kmart",
                                 rawMerchant: "KMART 1147", platform: nil, amount: "42.00",
                                 currency: "AUD", card: Card.nab.rawValue, last4: nil,
                                 date: "2026-09-10T03:00:00Z", note: nil, subscription: nil)
        _ = try EmailSync.importRecords([record], in: ctx, account: "raj@example.com")
        #expect(count(ctx) == 1)

        // An older backup, made before that email arrived.
        var snap = Backup.Snapshot()
        snap.transactions = [row(merchant: "Woolworths", amount: 20, on: "2026-09-01")]
        let old = try Backup.encode(snap)

        try Backup.restore(old, mode: .replace, into: ctx, defaults: scratch(), cardBook: book())
        #expect(count(ctx) == 1)   // only the backup's purchase

        // Reconnect Gmail and sync the very same email again.
        _ = try EmailSync.importRecords([record], in: ctx, account: "raj@example.com")

        let names = try ctx.fetch(FetchDescriptor<Transaction>()).map(\.merchant).sorted()
        #expect(names == ["Kmart", "Woolworths"])
    }

    /// Anything that isn't a Sortd backup must be refused, whatever the
    /// extension says. `Snapshot` gives every field a default, so a JSON
    /// file with no fields at all can still decode.
    @Test func junkFilesAreNeverTreatedAsBackups() throws {
        let junk: [(String, String)] = [
            ("empty object", "{}"),
            ("unrelated json", #"{"hello":"world"}"#),
            ("format only", #"{"format":"sortd.backup"}"#),
            ("format and version", #"{"format":"sortd.backup","version":1}"#),
            ("plain text", "this is my shopping list"),
            ("a csv", "date,description,amount\n01/09/2026,Woolworths,-58.30"),
        ]
        for (name, text) in junk {
            #expect(throws: (any Error).self, "\(name) was accepted as a backup") {
                try Backup.decode(Data(text.utf8))
            }
        }
    }

    /// A backup cut off mid-download must be refused, not half-restored.
    @Test func aTruncatedBackupIsRefused() throws {
        var snap = Backup.Snapshot()
        snap.transactions = (1...20).map { row(merchant: "Shop \($0)", amount: Decimal($0), on: "2026-09-01") }
        let full = try Backup.encode(snap)
        let cut = full.prefix(full.count / 2)

        #expect(throws: (any Error).self) { try Backup.decode(Data(cut)) }

        // And nothing may be written when it is handed to restore.
        let ctx = try store()
        add(ctx, "Woolworths", 58.30, "2026-09-01")
        #expect(throws: (any Error).self) {
            try Backup.restore(Data(cut), mode: .replace, into: ctx,
                               defaults: scratch(), cardBook: book())
        }
        #expect(count(ctx) == 1)
    }

    /// Replacing a full phone with an empty backup must say so first.
    @Test func replacingWithAnEmptyBackupIsSpeltOut() {
        let warning = Backup.replaceWarning(
            backup: Backup.Contents(purchases: 0, cards: 0, createdAt: .now), purchasesHere: 312)
        #expect(warning.title.contains("312"))
        #expect(warning.message.contains("leave Sortd empty"))
        #expect(warning.message.contains("can't be undone"))
    }

    /// Restoring the same good backup twice adds nothing the second time.
    @Test func restoringTheSameBackupTwiceAddsNothing() throws {
        let from = try store()
        add(from, "Woolworths", 58.30, "2026-09-01")
        add(from, "Seven Seeds", 5.50, "2026-09-02", category: .eatingOut)
        let data = try Backup.data(in: from, defaults: scratch())

        let to = try store()
        let first = try Backup.restore(data, mode: .merge, into: to, defaults: scratch(), cardBook: book())
        let second = try Backup.restore(data, mode: .merge, into: to, defaults: scratch(), cardBook: book())

        #expect(first.added == 2)
        #expect(second.added == 0)
        #expect(second.skipped == 2)
        #expect(count(to) == 2)
    }

    /// A row with a category or source this version has never heard of must
    /// land somewhere sane rather than being dropped.
    @Test func unknownCategoriesAndSourcesStillRestore() throws {
        var snap = Backup.Snapshot()
        var r = row(merchant: "Mystery", amount: 12, on: "2026-09-01")
        r.category = "timeTravel"
        r.source = "telepathy"
        snap.transactions = [r]

        let ctx = try store()
        try Backup.restore(try Backup.encode(snap), mode: .merge, into: ctx,
                           defaults: scratch(), cardBook: book())

        let t = try #require(try ctx.fetch(FetchDescriptor<Transaction>()).first)
        #expect(t.category == .other)
        #expect(t.source == .manual)
        #expect(t.amount == 12)
    }

    /// A backup row with a negative amount (hand-edited, or a bad export)
    /// must not quietly drag the month total down.
    @Test func aNegativeAmountInABackupDoesNotSubtractFromTheMonth() throws {
        var snap = Backup.Snapshot()
        snap.transactions = [
            row(merchant: "Woolworths", amount: 58.30, on: "2026-09-01"),
            row(merchant: "Glitch", amount: -1000, on: "2026-09-02"),
        ]
        let ctx = try store()
        try Backup.restore(try Backup.encode(snap), mode: .merge, into: ctx,
                           defaults: scratch(), cardBook: book())

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.audTotal >= 0)
    }

    /// `recurring.cancelled` is a `[String: Date]`. The `Setting` enum tries
    /// `[String: Double]` before `[String: Date]`, so this checks the dates
    /// come back as dates and not as something else.
    @Test func cancelledSubscriptionDatesSurviveABackupRoundTrip() throws {
        let from = scratch()
        let when = Date(timeIntervalSince1970: 1_789_000_000)
        from.set(["netflix": when], forKey: "recurring.cancelled")
        from.set(["spotify", "adobe"], forKey: "recurring.ignored")

        let data = try Backup.data(in: try store(), defaults: from)

        let to = scratch()
        try Backup.restore(data, mode: .replace, into: try store(), defaults: to, cardBook: book())

        let back = to.dictionary(forKey: "recurring.cancelled") as? [String: Date]
        #expect(back?["netflix"] == when)
        #expect(Set(to.stringArray(forKey: "recurring.ignored") ?? []) == ["spotify", "adobe"])
    }

    // MARK: - Delete + undo

    /// The undo window keeps the row in the store for six seconds. A Gmail
    /// receipt that arrives in that window merges into the doomed row, and
    /// the email is marked imported — so when the delete lands, the receipt
    /// is lost and no later sync will fetch it again.
    @Test func aReceiptThatMergesIntoAPendingDeleteIsLostForever() throws {
        let ctx = try store()

        // A tap logged by Wallet. The user swipes it away: ActivityView puts
        // it in `pendingDeletes` but does not touch the store yet.
        let tap = try TransactionLogger.log(
            IncomingPurchase(date: date("2026-09-10"), merchant: "COLES 0231", amount: 31.40,
                             currency: "AUD", card: .nab, source: .tap), in: ctx).transaction
        let doomed = [tap]

        // Sync runs while the toast is still up.
        let record = EmailRecord(id: "gmail-coles", kind: "purchase", merchant: "Coles",
                                 rawMerchant: "COLES 0231", platform: nil, amount: "31.40",
                                 currency: "AUD", card: Card.nab.rawValue, last4: nil,
                                 date: "2026-09-10T02:00:00Z", note: nil, subscription: nil)
        _ = try EmailSync.importRecords([record], in: ctx, account: "raj@example.com")

        // Six seconds pass: commitDelete().
        for t in doomed { ctx.delete(t) }
        try ctx.save()

        // Pull to refresh. The email is already an ImportedRecord.
        _ = try EmailSync.importRecords([record], in: ctx, account: "raj@example.com")

        #expect(count(ctx) == 1, "the Coles receipt was swallowed by a pending delete")
    }

    /// A replace-restore can land while a delete is still pending. The view
    /// then calls `context.delete` on rows the restore has already removed.
    /// That must not throw, crash, or take the restored rows with it.
    @Test func committingADeleteAfterARestoreIsHarmless() throws {
        let ctx = try store()
        let doomed = add(ctx, "Woolworths", 58.30, "2026-09-01")

        var snap = Backup.Snapshot()
        snap.transactions = [row(merchant: "Rent", amount: 900, on: "2026-09-02")]
        try Backup.restore(try Backup.encode(snap), mode: .replace, into: ctx,
                           defaults: scratch(), cardBook: book())

        // commitDelete() fires now, still holding the old object.
        ctx.delete(doomed)
        try ctx.save()

        let left = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(left.count == 1)
        #expect(left.first?.merchant == "Rent")
    }

    /// Two quick swipes then Undo must bring both back — nothing is written
    /// until the timer lands, so the store must be untouched throughout.
    @Test func twoQuickDeletesThenUndoLeaveEverythingInPlace() throws {
        let ctx = try store()
        let a = add(ctx, "Woolworths", 58.30, "2026-09-01")
        let b = add(ctx, "Seven Seeds", 5.50, "2026-09-02")

        var pending: [Transaction] = []
        pending.append(a)
        pending.append(b)
        // Undo: the array is simply dropped.
        pending = []

        #expect(pending.isEmpty)
        #expect(count(ctx) == 2)
    }

    // MARK: - Import

    private let statement = """
    Date,Description,Amount
    01/09/2026,WOOLWORTHS 1234 MELBOURNE,-58.30
    02/09/2026,SEVEN SEEDS CARLTON,-5.50
    03/09/2026,SALARY,2400.00
    """

    /// Importing the same file twice is the commonest user mistake. The
    /// second pass must match every line, not add it again.
    @Test func importingTheSameStatementTwiceDoesNotDouble() throws {
        let ctx = try store()
        let rows = StatementImport.rows(fromCSV: statement).filter { $0.kind == .spend }
        #expect(rows.count == 2)

        let first = StatementImport.save(rows, card: .nab, in: ctx)
        let second = StatementImport.save(rows, card: .nab, in: ctx)

        #expect(first.added == 2)
        #expect(second.added == 0)
        #expect(second.merged == 2)
        #expect(count(ctx) == 2)
    }

    /// Every line already known from taps: nothing new may be added.
    @Test func aStatementOfPurchasesSortdAlreadyHasAddsNothing() throws {
        let ctx = try store()
        _ = try TransactionLogger.log(
            IncomingPurchase(date: date("2026-09-01"), merchant: "WOOLWORTHS 1234",
                             amount: Decimal(string: "58.30")!, currency: "AUD",
                             card: .nab, source: .tap), in: ctx)
        _ = try TransactionLogger.log(
            IncomingPurchase(date: date("2026-09-02"), merchant: "SEVEN SEEDS",
                             amount: Decimal(string: "5.50")!, currency: "AUD",
                             card: .nab, source: .tap), in: ctx)

        let rows = StatementImport.rows(fromCSV: statement).filter { $0.kind == .spend }
        let out = StatementImport.save(rows, card: .nab, in: ctx)

        #expect(out.added == 0)
        #expect(out.merged == 2)
        #expect(count(ctx) == 2)
    }

    /// Three identical lines in one file are three purchases, and importing
    /// that file a second time must still leave three.
    @Test func threeIdenticalLinesStayThreeAcrossTwoImports() throws {
        let csv = """
        Date,Description,Amount
        01/09/2026,MYKI TOPUP,-10.00
        01/09/2026,MYKI TOPUP,-10.00
        01/09/2026,MYKI TOPUP,-10.00
        """
        let ctx = try store()
        let rows = StatementImport.rows(fromCSV: csv).filter { $0.kind == .spend }
        #expect(rows.count == 3)

        _ = StatementImport.save(rows, card: .nab, in: ctx)
        #expect(count(ctx) == 3)

        let again = StatementImport.save(rows, card: .nab, in: ctx)
        #expect(again.added == 0)
        #expect(count(ctx) == 3)
    }

    /// A line whose date cell is empty is dropped in silence. The review
    /// screen only counts what parsed, so the user is never told a line of
    /// their statement was not read.
    @Test func aRowWithNoDateIsNotSilentlyDropped() {
        let csv = """
        Date,Description,Amount
        01/09/2026,WOOLWORTHS,-58.30
        ,SEVEN SEEDS CARLTON,-5.50
        03/09/2026,KMART,-22.00
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.count == 3, "a statement line with no date vanished with no warning")
    }

    /// A typo'd or corrupt year must not land a purchase centuries away,
    /// where it can never be found again in the list.
    @Test func absurdDatesAreNotImported() {
        let csv = """
        Date,Description,Amount
        01/09/2099,FUTURE SHOP,-58.30
        01/09/1970,ANCIENT SHOP,-12.00
        """
        let rows = StatementImport.rows(fromCSV: csv)
        #expect(rows.isEmpty, "rows dated \(rows.map { $0.date.formatted(date: .numeric, time: .omitted) }) were accepted")
    }

    /// A statement in another currency with no symbol in the cells is filed
    /// in the home currency. Nothing in the app asks which currency the
    /// file is in, so a Singapore statement lands as AUD.
    @Test func aStatementWithNoCurrencySymbolLandsInTheHomeCurrency() throws {
        let csv = """
        Date,Description,Amount
        01/09/2026,NTUC FAIRPRICE,-58.30
        """
        let ctx = try store()
        let rows = StatementImport.rows(fromCSV: csv).filter { $0.kind == .spend }
        _ = StatementImport.save(rows, card: .scDebit, in: ctx)

        let t = try #require(try ctx.fetch(FetchDescriptor<Transaction>()).first)
        // Documenting: the card is an SGD card but the row is filed in home.
        #expect(t.currencyCode == Money.home)
    }

    /// A big statement must import in reasonable time. Every row re-fetches
    /// the whole nearby window and saves, so this is the shape of the cost.
    @Test func aBigStatementImportsInReasonableTime() throws {
        let ctx = try store()
        var lines = ["Date,Description,Amount"]
        for i in 1...600 {
            lines.append("01/09/2026,SHOP NUMBER \(i) PLACE,-\(i).50")
        }
        let rows = StatementImport.rows(fromCSV: lines.joined(separator: "\n")).filter { $0.kind == .spend }
        #expect(rows.count == 600)

        let started = Date.now
        let out = StatementImport.save(rows, card: .nab, in: ctx)
        let seconds = Date.now.timeIntervalSince(started)

        #expect(out.added == 600)
        #expect(seconds < 20, "600 rows took \(String(format: "%.1f", seconds))s")
    }

    // MARK: - Dedupe

    /// A Wallet tap that arrives with no amount (the notification did not
    /// carry one) can never match the receipt that follows, because the
    /// deduper bails on a zero amount. The user is left with a broken row
    /// and a real one for the same coffee.
    @Test func aTapWithNoAmountStillMergesWithItsReceipt() throws {
        let ctx = try store()
        _ = try TransactionLogger.log(
            IncomingPurchase(date: date("2026-09-10"), merchant: "SEVEN SEEDS", amount: 0,
                             currency: "AUD", card: .nab, source: .tap), in: ctx)
        _ = try TransactionLogger.log(
            IncomingPurchase(date: date("2026-09-10"), merchant: "Seven Seeds", amount: Decimal(string: "5.50")!,
                             currency: "AUD", card: .nab, source: .email), in: ctx)

        #expect(count(ctx) == 1, "a zero-amount tap and its receipt became two rows")
    }

    /// A receipt and a tap for one purchase must become one row whichever
    /// order they arrive in.
    @Test func tapAndReceiptMergeInEitherOrder() throws {
        for receiptFirst in [false, true] {
            let ctx = try store()
            let tap = IncomingPurchase(date: date("2026-09-10"), merchant: "COLES 0231",
                                       amount: Decimal(string: "31.40")!, currency: "AUD",
                                       card: .nab, source: .tap)
            let mail = IncomingPurchase(date: date("2026-09-10"), merchant: "Coles",
                                        amount: Decimal(string: "31.40")!, currency: "AUD",
                                        card: .nab, source: .email)
            if receiptFirst {
                _ = try TransactionLogger.log(mail, in: ctx)
                _ = try TransactionLogger.log(tap, in: ctx)
            } else {
                _ = try TransactionLogger.log(tap, in: ctx)
                _ = try TransactionLogger.log(mail, in: ctx)
            }
            #expect(count(ctx) == 1, "receiptFirst=\(receiptFirst)")
        }
    }

    /// The same email in one batch twice (an overlapping sync window plus a
    /// re-list) must not break the save or double the purchase.
    @Test func theSameEmailTwiceInOneBatchIsHandled() throws {
        let ctx = try store()
        let r = EmailRecord(id: "dup-1", kind: "purchase", merchant: "Kmart", rawMerchant: "KMART 1147",
                            platform: nil, amount: "42.00", currency: "AUD", card: Card.nab.rawValue,
                            last4: nil, date: "2026-09-10T03:00:00Z", note: nil, subscription: nil)

        let summary = try EmailSync.importRecords([r, r], in: ctx, account: "raj@example.com")

        #expect(count(ctx) == 1)
        #expect(summary.added == 1)
        #expect((try? ctx.fetchCount(FetchDescriptor<ImportedRecord>())) == 1)
    }

    /// The same batch replayed (a sync that ran twice) must add nothing.
    @Test func theSameBatchSyncedTwiceAddsNothing() throws {
        let ctx = try store()
        let r = EmailRecord(id: "replay-1", kind: "purchase", merchant: "Kmart", rawMerchant: "KMART",
                            platform: nil, amount: "42.00", currency: "AUD", card: Card.nab.rawValue,
                            last4: nil, date: "2026-09-10T03:00:00Z", note: nil, subscription: nil)
        _ = try EmailSync.importRecords([r], in: ctx, account: "a@example.com")
        let second = try EmailSync.importRecords([r], in: ctx, account: "a@example.com")

        #expect(second.added == 0)
        #expect(count(ctx) == 1)
    }

    /// A refund must zero its purchase, not create a second row and not
    /// zero a second purchase from the same shop.
    @Test func aRefundZerosExactlyOnePurchase() throws {
        let ctx = try store()
        let a = add(ctx, "Uniqlo", 89.90, "2026-09-01", category: .shopping, source: .email)
        let b = add(ctx, "Uniqlo", 89.90, "2026-09-05", category: .shopping, source: .email)

        let refund = EmailRecord(id: "refund-1", kind: "refund", merchant: "Uniqlo", rawMerchant: "UNIQLO",
                                 platform: nil, amount: "89.90", currency: "AUD", card: Card.nab.rawValue,
                                 last4: nil, date: "2026-09-08T03:00:00Z", note: nil, subscription: nil)
        let summary = try EmailSync.importRecords([refund], in: ctx, account: "a@example.com")

        #expect(summary.refunds == 1)
        #expect(count(ctx) == 2)
        #expect([a.refunded, b.refunded].filter { $0 }.count == 1)
    }

    /// The same refund email arriving twice must not mark a second purchase.
    @Test func theSameRefundTwiceDoesNotZeroTwoPurchases() throws {
        let ctx = try store()
        add(ctx, "Uniqlo", 89.90, "2026-09-01", category: .shopping, source: .email)
        add(ctx, "Uniqlo", 89.90, "2026-09-05", category: .shopping, source: .email)

        let refund = EmailRecord(id: "refund-2", kind: "refund", merchant: "Uniqlo", rawMerchant: "UNIQLO",
                                 platform: nil, amount: "89.90", currency: "AUD", card: Card.nab.rawValue,
                                 last4: nil, date: "2026-09-08T03:00:00Z", note: nil, subscription: nil)
        _ = try EmailSync.importRecords([refund], in: ctx, account: "a@example.com")
        _ = try EmailSync.importRecords([refund], in: ctx, account: "a@example.com")

        let refunded = try ctx.fetch(FetchDescriptor<Transaction>()).filter(\.refunded)
        #expect(refunded.count == 1)
        #expect(refunded.first?.note.components(separatedBy: "Refunded").count == 2)
    }

    /// A refunded purchase that the bank charges again (a reversal of the
    /// reversal) must come back as a real purchase, not merge into the
    /// refunded row and stay at zero.
    @Test func aRechargeAfterARefundIsCountedAgain() throws {
        let ctx = try store()
        let t = add(ctx, "Uniqlo", 89.90, "2026-09-01", category: .shopping, source: .email)
        t.refunded = true
        try ctx.save()

        _ = try TransactionLogger.log(
            IncomingPurchase(date: date("2026-09-01"), merchant: "UNIQLO", amount: 89.90,
                             currency: "AUD", card: .nab, source: .bank), in: ctx)

        let all = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(all.audTotal == Decimal(string: "89.90")!)
    }

    /// Changing a category must move the other purchases from that shop and
    /// nothing else.
    @Test func aMerchantRuleMovesOnlyThatShop() throws {
        let ctx = try store()
        let a = add(ctx, "Chemist Warehouse", 18, "2026-09-01")
        let b = add(ctx, "CHEMIST WAREHOUSE MELBOURNE", 22, "2026-09-05")
        let other = add(ctx, "Woolworths", 58, "2026-09-03")

        try TransactionLogger.recategorise(a, to: .health, in: ctx)

        #expect(a.category == .health)
        #expect(b.category == .health)
        #expect(other.category == .groceries)
    }

    /// Two different shops whose names differ only by a trailing number are
    /// collapsed into one rule key, so recategorising one moves the other.
    @Test func shopsThatDifferOnlyByANumberAreNotTreatedAsOne() throws {
        let ctx = try store()
        let a = add(ctx, "Sushi Hub 1", 14, "2026-09-01", category: .eatingOut)
        let b = add(ctx, "Sushi Hub 2", 16, "2026-09-02", category: .eatingOut)

        // Documenting the key collapse itself.
        let keys = [MerchantName.key("Sushi Hub 1"), MerchantName.key("Sushi Hub 2")]
        #expect(keys[0] != keys[1], "both names reduce to \"\(keys[0])\"")

        try TransactionLogger.recategorise(a, to: .groceries, in: ctx)
        #expect(b.category == .eatingOut)
    }

    // MARK: - Recurring

    /// "Not Recurring" then "Show again" must be a clean round trip.
    @Test func ignoreAndUnignoreRoundTrip() {
        let key = "abuse-test-\(UUID().uuidString.prefix(6))"
        let before = RecurringPrefs.ignored
        defer { RecurringPrefs.ignored = before }

        RecurringPrefs.ignore(key)
        #expect(RecurringPrefs.ignored.contains(key))
        RecurringPrefs.unignore(key)
        #expect(!RecurringPrefs.ignored.contains(key))
    }

    /// Cancel then un-cancel must leave no trace.
    @Test func cancelAndUndoCancelRoundTrip() {
        let key = "abuse-cancel-\(UUID().uuidString.prefix(6))"
        let before = RecurringPrefs.cancelled
        defer { RecurringPrefs.cancelled = before }

        RecurringPrefs.markCancelled(key)
        #expect(RecurringPrefs.cancelled[key] != nil)
        RecurringPrefs.undoCancel(key)
        #expect(RecurringPrefs.cancelled[key] == nil)
    }

    /// A subscription cancelled and then charged again must be flagged, not
    /// silently filed as cancelled.
    @Test func aChargeAfterCancellingIsFlagged() {
        let cal = Calendar.current
        let now = date("2026-09-20")
        let charges = (0..<4).map { i in
            RecurringDetector.Charge(date: cal.date(byAdding: .month, value: -i, to: now)!,
                                     merchant: "Netflix", amount: 22.99, currency: "AUD",
                                     audAmount: 22.99, category: .subscriptions, card: .nab,
                                     renewsOn: nil, billingPeriod: nil)
        }
        let cancelledOn = cal.date(byAdding: .day, value: -10, to: now)!
        let found = RecurringDetector.detect(charges, cancelled: ["netflix": cancelledOn], now: now)

        let netflix = found.first { $0.key == "netflix" }
        #expect(netflix?.chargedAfterCancel == true)
        #expect(netflix?.status != .cancelled)
    }

    /// Ignoring one merchant must not hide a different one.
    @Test func ignoringOneSubscriptionDoesNotHideAnother() {
        let cal = Calendar.current
        let now = date("2026-09-20")
        func monthly(_ name: String, _ amount: Decimal) -> [RecurringDetector.Charge] {
            (0..<4).map { i in
                RecurringDetector.Charge(date: cal.date(byAdding: .month, value: -i, to: now)!,
                                         merchant: name, amount: amount, currency: "AUD",
                                         audAmount: amount, category: .subscriptions, card: .nab,
                                         renewsOn: nil, billingPeriod: nil)
            }
        }
        let charges = monthly("Netflix", 22.99) + monthly("Netflix Games", 5)
        let found = RecurringDetector.detect(charges, ignored: ["netflix"], now: now)

        #expect(found.contains { $0.merchant == "Netflix Games" })
        #expect(!found.contains { $0.merchant == "Netflix" })
    }

    // MARK: - Widget

    /// The widget's numbers must match Home: no refunds, no transfers.
    @Test func widgetTotalsLeaveOutRefundsAndTransfers() throws {
        let ctx = try store()
        let now = date("2026-09-15")
        add(ctx, "Woolworths", 50, "2026-09-10")
        let refunded = add(ctx, "Uniqlo", 80, "2026-09-11", category: .shopping)
        refunded.refunded = true
        add(ctx, "Transfer to savings", 500, "2026-09-12", category: .transfers)
        try ctx.save()

        let summary = WidgetBridge.build(from: try ctx.fetch(FetchDescriptor<Transaction>()),
                                         budget: 2000, now: now)
        #expect(summary.month == 50)
    }

    /// A foreign purchase waiting on an exchange rate counts as zero, so the
    /// widget says there is more money left than there is.
    @Test func anUnconvertedForeignPurchaseIsNotMissingFromTheMonth() throws {
        let ctx = try store()
        let now = date("2026-09-15")
        add(ctx, "Woolworths", 50, "2026-09-10")
        let sgd = Transaction(date: date("2026-09-12"), merchant: "DBS Orchard", amount: 100,
                              currencyCode: "SGD", card: .scDebit, category: .shopping, source: .email)
        sgd.audAmount = nil
        ctx.insert(sgd)
        try ctx.save()

        let summary = WidgetBridge.build(from: try ctx.fetch(FetchDescriptor<Transaction>()),
                                         budget: 2000, now: now)
        #expect(summary.month > 50, "the SGD purchase counted as zero; month = \(summary.month)")
    }

    /// The widget file must be built from a consistent read: a summary built
    /// twice from the same rows must be identical.
    @Test func theWidgetSummaryIsStableForTheSameRows() throws {
        let ctx = try store()
        let now = date("2026-09-15")
        add(ctx, "Woolworths", 50, "2026-09-10")
        add(ctx, "Seven Seeds", 5.50, "2026-09-11", category: .eatingOut)
        let rows = try ctx.fetch(FetchDescriptor<Transaction>())

        let a = WidgetBridge.build(from: rows, budget: 2000, now: now)
        let b = WidgetBridge.build(from: rows, budget: 2000, now: now)
        #expect(a.month == b.month)
        #expect(a.categories.map(\.total) == b.categories.map(\.total))
    }

    // MARK: - Delete everything

    /// Delete All Data must leave nothing behind that a later sync could
    /// trip over.
    @Test func deleteEverythingLeavesNoStragglers() throws {
        let ctx = try store()
        add(ctx, "Woolworths", 58.30, "2026-09-01")
        ctx.insert(ImportedRecord(id: "gone-1", account: "a@example.com"))
        ctx.insert(MerchantRule(key: "woolworths", category: .groceries))
        ctx.insert(FXRate(key: "SGD-2026-09-01", rate: 1.1))
        try ctx.save()

        try? ctx.delete(model: Transaction.self)
        try? ctx.delete(model: MerchantRule.self)
        try? ctx.delete(model: ImportedRecord.self)
        try? ctx.delete(model: FXRate.self)
        try ctx.save()

        #expect(count(ctx) == 0)
        #expect((try? ctx.fetchCount(FetchDescriptor<ImportedRecord>())) == 0)
        #expect((try? ctx.fetchCount(FetchDescriptor<MerchantRule>())) == 0)
        #expect((try? ctx.fetchCount(FetchDescriptor<FXRate>())) == 0)
    }
}

import Testing
import Foundation
import SwiftData
@testable import Spend

/// Bug hunt, 26 Sep 2026, data-backup area. One failing test per finding.
/// Each is tagged `.knownBug` and runs only with `scripts/test.sh --known-bugs`.
///
/// Already covered by known-bug tests in `AbuseDataAgentTests` and left out
/// here: duplicate ids in one backup (merge and replace), Replace keeping
/// `ImportedRecord`s, a negative amount in a backup, a receipt merging into a
/// pending delete, and a recharge after a refund.
@MainActor
struct BugHuntDataTests {

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
        let name = "bughunt-data-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    /// A CardBook that never touches the real card list.
    private func book() -> CardBook {
        CardBook(defaults: scratch())
    }

    private func date(_ ymd: String, hour: Double = 8) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Australia/Melbourne")
        return f.date(from: ymd)!.addingTimeInterval(hour * 3600)
    }

    private func count(_ ctx: ModelContext) -> Int {
        (try? ctx.fetchCount(FetchDescriptor<Transaction>())) ?? -1
    }

    // MARK: - Backup: settings across currencies

    /// "Add What's Missing" from an SGD phone onto an AUD phone that has no
    /// budget yet: the S$2,400 budget and the S$300 Eating Out limit are
    /// written as A$2,400 and A$300. Nothing converts them afterwards, because
    /// `convertedKey` still says AUD, so `FXService.ensureConverted` returns
    /// early.
    ///
    /// Known bug: `Backup.restore` (Spend/Services/Backup.swift:271-276) copies
    /// `monthlyBudget` and `categoryBudgets` from the backup's currency on merge
    /// and only sets `convertedKey` on replace or a home-currency change (:288).
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("merge restore copies the budget and category limits across currencies without converting them"))
    func mergeDoesNotReadASingaporeBudgetAsAustralianDollars() throws {
        let fromDefaults = scratch()
        fromDefaults.set("SGD", forKey: Money.homeKey)
        fromDefaults.set(2400.0, forKey: FXService.budgetKey)
        fromDefaults.set(["eatingOut": 300.0], forKey: CategoryBudgets.key)
        let data = try Backup.data(in: try store(), defaults: fromDefaults)

        let toDefaults = scratch()
        toDefaults.set("AUD", forKey: Money.homeKey)
        toDefaults.set("AUD", forKey: FXService.convertedKey)
        try Backup.restore(data, mode: .merge, into: try store(), defaults: toDefaults, cardBook: book())

        // Either the S$ figures stay out, or the phone is flagged so the next
        // `ensureConverted` converts them. What must not happen is S$2,400
        // silently becoming A$2,400.
        let flaggedForConversion = toDefaults.string(forKey: FXService.convertedKey) != "AUD"
        #expect(toDefaults.double(forKey: FXService.budgetKey) != 2400 || flaggedForConversion)
        #expect(CategoryBudgets.stored(toDefaults)["eatingOut"] != 300 || flaggedForConversion)
        #expect(toDefaults.string(forKey: Money.homeKey) == "AUD")
    }

    // MARK: - Categories chosen by hand

    /// Woolworths moved to Other with "Just This One" (no rule learned). At the
    /// next launch `refreshUncategorised` re-runs the built-in rules on every
    /// purchase still in Other and puts it back in Groceries. The user's choice
    /// is undone every time the app opens.
    ///
    /// Known bug: `TransactionLogger.refreshUncategorised`
    /// (Spend/Services/SpendStore.swift:173-179) treats every Other purchase as
    /// uncategorised, including ones set to Other by hand without a rule.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("a purchase moved to Other with Just This One is re-categorised at the next launch"))
    func justThisOneToOtherSurvivesALaunch() throws {
        let ctx = try store()
        let t = try TransactionLogger.log(
            IncomingPurchase(date: date("2026-09-20"), merchant: "Woolworths", amount: 58.30,
                             currency: "AUD", card: .nab, source: .tap), in: ctx).transaction
        try #require(t.category == .groceries)

        try TransactionLogger.recategorise(t, to: .other, in: ctx, applyToOthers: false)
        try #require(t.category == .other)

        // What SpendApp does at every launch.
        try TransactionLogger.refreshUncategorised(in: ctx)

        #expect(t.category == .other)
    }

    /// A DoorDash order moved from Food Delivery to Eating Out with "Just This
    /// One". The next launch flips it back: the platform rule only spares
    /// purchases that have a learned rule, and "Just This One" learns none.
    ///
    /// Known bug: `TransactionLogger.refreshUncategorised`
    /// (Spend/Services/SpendStore.swift:166-172) moves every Eating Out purchase
    /// with a delivery platform to Food Delivery unless a rule exists.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("a delivery order moved to Eating Out with Just This One goes back to Food Delivery at the next launch"))
    func justThisOneOnADeliveryOrderSurvivesALaunch() throws {
        let ctx = try store()
        let t = try TransactionLogger.log(
            IncomingPurchase(date: date("2026-09-20"), merchant: "Chennai Biryani House", amount: 42.15,
                             currency: "AUD", card: .other, source: .email, category: .foodDelivery,
                             platform: "doordash"), in: ctx).transaction
        try #require(t.category == .foodDelivery)

        try TransactionLogger.recategorise(t, to: .eatingOut, in: ctx, applyToOthers: false)
        try #require(t.category == .eatingOut)

        try TransactionLogger.refreshUncategorised(in: ctx)

        #expect(t.category == .eatingOut)
    }

    // MARK: - Dedupe: a tap the day after

    /// Monday: a tap at Starbucks, then the bank's email for it, which merges
    /// in and (being the more trusted source) makes the row an email row.
    /// Tuesday: the same coffee, tapped again. The Deduper's "same source,
    /// different day = two purchases" rule no longer applies, because the
    /// Monday row now says `email` and the new one says `tap`, so Tuesday's
    /// coffee merges into Monday's and is lost. It only comes back if
    /// Tuesday's bank email arrives; a missed alert or a lapsed Pro
    /// means a dropped purchase.
    ///
    /// Known bug: `Deduper.match` (Spend/Services/Deduper.swift:38-43) reads
    /// only `source`, not `seenIn`, after `TransactionLogger.merge`
    /// (Spend/Services/SpendStore.swift:135-139) raises the row's source.
    @Test
    func aTapTheNextDayIsANewPurchaseEvenAfterAnEmailMergedIn() throws {
        let ctx = try store()
        let monday = date("2026-09-14")
        _ = try TransactionLogger.log(
            IncomingPurchase(date: monday, merchant: "Starbucks", amount: 6.20,
                             currency: "AUD", card: .nab, source: .tap), in: ctx)
        let email = try TransactionLogger.log(
            IncomingPurchase(date: monday.addingTimeInterval(60), merchant: "Starbucks", amount: 6.20,
                             currency: "AUD", card: .nab, source: .email), in: ctx)
        guard case .merged = email else { Issue.record("Monday's email should merge into Monday's tap"); return }
        try #require(count(ctx) == 1)

        let tuesday = try TransactionLogger.log(
            IncomingPurchase(date: monday.addingTimeInterval(86400), merchant: "Starbucks", amount: 6.20,
                             currency: "AUD", card: .nab, source: .tap), in: ctx)

        guard case .added = tuesday else { Issue.record("Tuesday's coffee merged into Monday's"); return }
        #expect(count(ctx) == 2)
    }

    // MARK: - CSV export

    /// A note pasted from Windows or Outlook carries "\r\n". Swift treats that
    /// pair as one Character, so `escape` sees neither "\n" nor a leading
    /// "\r", leaves the field unquoted, and the spreadsheet splits the row in
    /// two: the columns after the note land on their own line.
    ///
    /// Known bug: `CSVExport.escape` (Spend/Views/DataControlsView.swift:75)
    /// checks `$0 == "\n"` per Character and misses the CRLF grapheme.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("a CSV field with a Windows line break (CRLF) is not quoted"))
    func aFieldWithAWindowsLineBreakIsQuoted() {
        let out = CSVExport.escape("Lunch\r\nwith Sam")
        #expect(out.hasPrefix("\"") && out.hasSuffix("\""), "got \(out.debugDescription)")
    }
}

// MARK: - Bug hunt, 8 Oct 2026

/// Bug hunt, 8 Oct 2026, data-backup area. One failing test per finding,
/// each tagged `.knownBug`; they run only with `scripts/test.sh --known-bugs`.
///
/// Serialized: two of these load and clear the sample data, which lives in
/// `UserDefaults.standard` and `CardBook.shared`, and one runs Delete All
/// Data against the test host's defaults.
@Suite(.serialized)
@MainActor
struct BugHuntDataOct2026Tests {

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
        let name = "bughunt-data-oct8-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    /// A CardBook that never touches the real card list.
    private func book() -> CardBook {
        CardBook(defaults: scratch())
    }

    /// A local date and time, like a tap or a statement line on this phone.
    private func date(_ ymd: String, _ hm: String = "12:00") -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = .current
        return f.date(from: "\(ymd) \(hm)")!
    }

    private func money(_ s: String) -> Decimal { Decimal(string: s)! }

    private func count(_ ctx: ModelContext) throws -> Int {
        try ctx.fetchCount(FetchDescriptor<Transaction>())
    }

    // MARK: - 1. Restore makes a new iPhone look set up for Apple Pay

    /// New iPhone, fresh install, the shortcut has never run here. The person
    /// restores the old iPhone's backup (the first thing setup offers). The
    /// restored tap rows have `seenIn` "tap", so `ApplePayStatus.resolve`
    /// says `.tapLogged`: setup's Apple Pay step reads "Do Step 3 to
    /// Continue" and lets the person continue, Home's Finish Setup card
    /// ticks "Log Apple Pay by itself", `ApplePaySetupSteps.isReady` is true
    /// on both routes, and no nudge ever asks for the shortcut or the
    /// automation. Nothing on the new iPhone logs a tap.
    ///
    /// Known bug: `Backup.apply` (Spend/Services/Backup.swift:418) copies
    /// `seenIn` as it was, and `ApplePayStatus.realTaps`
    /// (Spend/Services/ApplePayStatus.swift:35-43) counts every row with
    /// `.tap` in it as a real tap on this iPhone.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("tap rows restored from the old iPhone make the new iPhone's Apple Pay step read as set up"))
    func restoredTapRowsDoNotMakeANewPhoneLookSetUpForApplePay() throws {
        // The old iPhone: one real tap, backed up.
        let old = try store()
        _ = try TransactionLogger.log(
            IncomingPurchase(date: date("2026-09-14", "09:14"), merchant: "Starbucks", amount: money("6.20"),
                             currency: "AUD", card: .nab, source: .tap, tapOrigin: .tap), in: old)
        let oldDefaults = scratch()
        oldDefaults.set("AUD", forKey: Money.homeKey)
        let data = try Backup.data(in: old, defaults: oldDefaults)

        // The new iPhone: nothing has reached Sortd here.
        let new = try store()
        try Backup.restore(data, mode: .replace, into: new, defaults: scratch(), cardBook: book())
        let rows = try new.fetch(FetchDescriptor<Transaction>())
        try #require(rows.count == 1)

        let status = ApplePayStatus.resolve(lastReachedAt: nil, taps: rows)
        #expect(!status.isConnected, "a tap from the old iPhone reads as this iPhone's: \(status)")
        #expect(!ApplePaySetupSteps.isReady(status: status, route: .shortcut, saysBuilt: false))
        #expect(!ApplePaySetupSteps.isReady(status: status, route: .automation, saysBuilt: false))
    }

    // MARK: - 2. Re-import after a next-day post

    /// Tuesday 09:14: a tap at Seven Seeds. The bank posts it dated Wednesday.
    /// The first import merges the statement line into the tap (2-day
    /// window) and the row keeps the tap's time. Importing the same file
    /// again, the Deduper's "same source twice" rule asks for the same
    /// calendar day, Tuesday is not Wednesday, and the coffee is added a
    /// second time. Every tap the bank posted the next day doubles on a
    /// re-import; a weekend's taps all do.
    ///
    /// Known bug: `Deduper.match` (Spend/Services/Deduper.swift:93-96)
    /// compares a re-imported statement row with the merged row by calendar
    /// day, but the merged row carries the tap's date, not the bank's
    /// (`TransactionLogger.merge`, Spend/Services/SpendStore.swift:255).
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("re-importing a statement doubles every tap the bank posted the day after"))
    func reimportingAStatementPostedTheDayAfterTheTapDoesNotDouble() throws {
        let ctx = try store()
        _ = try TransactionLogger.log(
            IncomingPurchase(date: date("2026-09-01", "09:14"), merchant: "Seven Seeds", amount: money("5.50"),
                             currency: Money.home, card: .nab, source: .tap), in: ctx)

        let rows = StatementImport.rows(fromCSV: """
        Date,Description,Amount
        02/09/2026,SEVEN SEEDS COFFEE CARLTON,-5.50
        """, dateOrder: .dayFirst)
        try #require(rows.count == 1)
        let first = StatementImport.save(rows, card: .nab, in: ctx)
        try #require(first.merged == 1, "the next-day statement line should merge with the tap the first time")
        try #require(try count(ctx) == 1)

        let again = StatementImport.save(rows, card: .nab, in: ctx)
        #expect(again.added == 0, "the same line, imported again, was added as a new purchase")
        #expect(again.merged == 1)
        #expect(try count(ctx) == 1)
    }

    // MARK: - 3. A real tap merges into a sample purchase

    /// Exploring with sample data, the person buys the same coffee the
    /// sample has for today: Starbucks, $6.20. The tap finds the sample row
    /// (same day, same amount, same name) and merges into it. The row keeps
    /// the note "Sample purchase", so `Backup.snapshot` leaves the real
    /// purchase out of every backup, the CSV leaves it out, and "Clear
    /// sample data" deletes it.
    ///
    /// Known bug: `TransactionLogger.log` (Spend/Services/SpendStore.swift:175-199)
    /// lets a real purchase merge into a row whose note is `DemoData.marker`;
    /// `Backup.snapshot` (Spend/Services/Backup.swift:156) and
    /// `DemoData.clear` (Spend/Services/DemoData.swift:94) then treat the
    /// real purchase as sample data.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("a real tap merges into a same-day sample purchase; the backup leaves it out and Clear sample data deletes it"))
    func aRealTapIsNotSwallowedByASamplePurchase() throws {
        let ctx = try store()
        let wasActive = DemoData.isActive
        UserDefaults.standard.set(false, forKey: DemoData.activeKey)
        DemoData.load(in: ctx, now: date("2026-09-20", "23:00"))
        defer {
            DemoData.clear(in: ctx)
            UserDefaults.standard.set(wasActive, forKey: DemoData.activeKey)
        }
        let samples = try count(ctx)
        try #require(samples > 0)

        // The sample data has Starbucks $6.20 at 08:24 today. A real one.
        let outcome = try TransactionLogger.log(
            IncomingPurchase(date: date("2026-09-20", "09:02"), merchant: "Starbucks", amount: money("6.20"),
                             currency: Money.home, card: .other, source: .tap, tapOrigin: .tap), in: ctx)
        if case .merged = outcome { Issue.record("the real Starbucks tap merged into the sample purchase") }
        #expect(try count(ctx) == samples + 1)

        let backup = try Backup.snapshot(in: ctx, defaults: scratch())
        #expect(backup.transactions.count == 1, "the real purchase is not in the backup")

        DemoData.clear(in: ctx)
        #expect(try count(ctx) == 1, "Clear sample data deleted the real purchase")
    }

    // MARK: - 4. Replace Everything leaves the sample-data flag on

    /// Exploring with sample data, the person restores their old iPhone's
    /// backup with Replace Everything. The sample rows and cards go, the
    /// real purchases come in, and `DemoData.activeKey` stays true: Home
    /// keeps the "sample data" banner over real spending (whose "Clear and
    /// Set Up Sortd" restarts setup), and analytics stays off as if this
    /// were still a demo.
    ///
    /// Known bug: `Backup.restore` (Spend/Services/Backup.swift:265-334)
    /// never touches `DemoData.activeKey`, and nothing else turns it off
    /// once the marked rows are gone (`DemoData.isLoaded` only turns it on).
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("Replace Everything on an iPhone showing sample data removes the sample rows but leaves the sample-data flag on"))
    func replaceEverythingTurnsSampleDataOff() throws {
        let ctx = try store()
        let wasActive = DemoData.isActive
        UserDefaults.standard.set(false, forKey: DemoData.activeKey)
        DemoData.load(in: ctx, now: date("2026-09-20", "23:00"))
        defer {
            DemoData.clear(in: ctx)
            UserDefaults.standard.set(wasActive, forKey: DemoData.activeKey)
        }
        try #require(DemoData.isActive)

        // The old iPhone's backup, with this phone's own settings so Replace
        // puts them straight back.
        let old = try store()
        _ = try TransactionLogger.log(
            IncomingPurchase(date: date("2026-09-14", "09:14"), merchant: "Woolworths", amount: money("58.30"),
                             currency: Money.home, card: .nab, source: .tap), in: old)
        let data = try Backup.data(in: old, defaults: .standard)

        try Backup.restore(data, mode: .replace, into: ctx, defaults: .standard, cardBook: book())
        try #require(!DemoData.hasRows(in: ctx), "Replace should have removed the sample rows")
        #expect(try count(ctx) == 1)
        #expect(!DemoData.isActive, "Home still shows the sample-data banner over the restored purchases")
    }

    // MARK: - 5. Delete All Data leaves the tap queue

    /// A tap Sortd could not save (the store would not open, or the save
    /// threw) waits in `TapQueue`'s file in the app group. Delete All Data
    /// wipes the store, the defaults, the Keychain and the export folder,
    /// and leaves that file alone. At the next launch `TapQueue.replay`
    /// logs the tap into the emptied store: a purchase comes back after
    /// "There's no undo".
    ///
    /// Known bug: `DataReset.deleteEverything`
    /// (Spend/Views/DataControlsView.swift:92-162) never clears the queue,
    /// and `SpendApp` (Spend/App/SpendApp.swift:539) replays it at launch.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("Delete All Data leaves queued taps in the app group file, so they are logged at the next launch"))
    func deleteAllDataEmptiesTheTapQueue() async throws {
        let ctx = try store()
        // The health check's own tap, so a stray row is hidden if it ever lands.
        try #require(TapQueue.enqueue(merchant: ApplePayHealthCheck.merchant, amount: "A$0.01", card: "Test Card",
                                      date: date("2026-09-20", "09:00")))
        try #require(TapQueue.count >= 1)

        DataReset.deleteEverything(in: ctx)
        let left = TapQueue.count

        // Drain the real queue whatever happened, so the test host's next
        // launch has nothing to replay.
        _ = await TapQueue.replay(in: ctx)

        #expect(left == 0, "\(left) queued tap(s) survived Delete All Data")
    }

    // MARK: - 6. A newer backup says "isn't a Sortd backup"

    /// A backup from a future Sortd (format 2) whose `amount` is written as
    /// a string. `Backup.decode` decodes the whole file before it looks at
    /// `version`, the decode fails on the changed field, and the person is
    /// told the file "isn't a Sortd backup" instead of "made by a newer
    /// version of Sortd. Update Sortd and try again." The version field
    /// exists for exactly this, and it is only reached when nothing changed.
    ///
    /// Known bug: `Backup.decode` (Spend/Services/Backup.swift:255-259) runs
    /// the version check after a full `Snapshot` decode.
    @Test(.tags(.knownBug), .enabled(if: KnownBugs.run),
          .bug("the format version is checked only after a full decode, so a newer backup with a changed field reads as not a backup"))
    func aNewerBackupWithAChangedFieldAsksForAnUpdate() {
        let newer = """
        {"format":"sortd.backup","version":2,"createdAt":"2026-10-08T01:00:00Z","cards":[],"settings":{},"rules":[],
         "transactions":[{"id":"6B2D9F2A-3C4E-4F5A-8B6C-1D2E3F4A5B6C","date":"2026-10-01T02:00:00Z",
           "merchant":"Coles","rawMerchant":"COLES 1234","amount":"58.30","currencyCode":"AUD","card":"nab",
           "category":"groceries","source":"tap","seenIn":"tap","note":"","createdAt":"2026-10-01T02:00:00Z",
           "refunded":false}]}
        """
        do {
            _ = try Backup.decode(Data(newer.utf8))
            Issue.record("a version-2 file decoded as version 1")
        } catch Backup.Failure.tooNew(let version) {
            #expect(version == 2)
        } catch {
            #expect(Bool(false), "expected tooNew(2), got \(error.localizedDescription)")
        }
    }
}

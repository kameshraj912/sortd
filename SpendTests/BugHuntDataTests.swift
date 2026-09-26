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
    /// Tuesday's bank email arrives; a missed alert, a disconnected Gmail or
    /// a lapsed Pro means a dropped purchase.
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

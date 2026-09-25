import Testing
import Foundation
import SwiftData
import UserNotifications
@testable import Spend

/// Pins behaviours from `docs/specs/2026-09-25-free-app-overhaul-1-free.md`
/// (sub-spec 1: the whole app is free). Everything Pro used to gate --
/// reminders, category-limit alerts, the bills Siri answer -- now works with
/// no Pro condition at all.
@MainActor
struct FreeAppTests {

    // MARK: Category limits

    private func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    /// `Reminders.checkCategoryLimits` (`Spend/Services/Reminders.swift:105`
    /// today) still guards on `ProStore.shared.isPro`. In the test process
    /// nothing is ever purchased, so with the gate still in place this stays
    /// red: it never records the over-limit alert even though a category is
    /// well over its limit and reminders are on.
    ///
    /// Asserts on `CategoryBudgets.sentAlerts`, not on
    /// `UNUserNotificationCenter.pendingNotificationRequests()`: the unit
    /// test host has no notification authorization on this simulator (no
    /// UI to grant it, and `simctl privacy` has no `notifications` service),
    /// so `center.add` always fails here regardless of the Pro gate.
    /// `saveSentAlerts` runs right after the same gate this test is about,
    /// before the OS call, so it is a reliable stand-in for "an alert fired".
    @Test func categoryLimitCheckHasNoProCondition() async throws {
        let standardDefaults = UserDefaults.standard
        let wasEnabled = standardDefaults.bool(forKey: Reminders.enabledKey)
        standardDefaults.set(true, forKey: Reminders.enabledKey)
        defer { standardDefaults.set(wasEnabled, forKey: Reminders.enabledKey) }

        // The test host's home currency depends on the simulator's region
        // (e.g. SGD on en_SG); logging in a hardcoded "AUD" would leave
        // audValue at 0 on a non-AUD host and fail for FX reasons, not the
        // Pro condition this test is about. Pin the home currency and log
        // the purchase in it.
        let wasHome = standardDefaults.string(forKey: Money.homeKey)
        standardDefaults.set("AUD", forKey: Money.homeKey)
        defer {
            if let wasHome { standardDefaults.set(wasHome, forKey: Money.homeKey) }
            else { standardDefaults.removeObject(forKey: Money.homeKey) }
        }

        let context = try store()
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let purchase = IncomingPurchase(date: now, merchant: "Woolworths", amount: 500, currency: Money.home,
                                        card: .other, source: .email)
        let txn = try TransactionLogger.log(purchase, in: context).transaction

        let limits = UserDefaults(suiteName: "FreeAppTests-limits-\(UUID().uuidString)")!
        CategoryBudgets.set(50, for: txn.category, limits)

        await Reminders.checkCategoryLimits([txn], now: now, defaults: limits)

        #expect(!CategoryBudgets.sentAlerts(limits).isEmpty, "expected an over-limit alert with no Pro purchased")
    }

    // MARK: Upcoming bills, Siri

    /// `UpcomingBillsIntent.perform()` (`Spend/Intents/SpendQuestionIntents.swift:124`
    /// today) answers "Upcoming bills are part of Sortd Pro..." when
    /// `ProStore.shared.isPro` is false. The free app always gives the real
    /// answer, so that literal string must be gone from the source.
    @Test func upcomingBillsAnswerNeverMentionsPro() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Spend/Intents/SpendQuestionIntents.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(!source.contains("Sortd Pro"))
    }

    /// The pure answer builder behind the intent never mentions Pro either --
    /// this one already passes and pins that it stays that way.
    @Test func upcomingBillsPureAnswerNeverMentionsPro() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let nextDate = now.addingTimeInterval(86_400)
        let bill = Recurring(key: "netflix", merchant: "Netflix", category: .subscriptions, card: .other,
                             cadence: .monthly, amount: 15.99, currency: "AUD", audAmount: 15.99,
                             lastDate: now, nextDate: nextDate, charges: 3, previousAmount: nil,
                             status: .active, chargedAfterCancel: false)
        let text = SpendSummary.upcomingBills([bill], hasPurchases: true, now: now)
        #expect(!text.contains("Pro"))
    }

    // MARK: Source scan

    /// Script-level check the builder must satisfy before this sub-spec is
    /// done: nothing under `Spend/` still mentions Pro, the paywall, or
    /// entitlements. This is expected to fail today -- the whole point of
    /// the overhaul is to remove every one of these.
    @Test func sourceTreeHasNoProOrPaywallReferences() throws {
        let spendRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Spend")
        let pattern = try NSRegularExpression(
            pattern: "isPro|ProStore|PaywallView|ProGate|SORTD_BETA|CompedPro|currentEntitlements")
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: spendRoot, includingPropertiesForKeys: [.isRegularFileKey]) else {
            Issue.record("could not enumerate \(spendRoot.path)")
            return
        }
        var hits: [String] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }          // skips SortdTips.storekit too
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if pattern.firstMatch(in: text, range: range) != nil {
                hits.append(url.path.replacingOccurrences(of: spendRoot.deletingLastPathComponent().path + "/", with: ""))
            }
        }
        #expect(hits.isEmpty, "found matches in: \(hits.sorted())")
    }
}

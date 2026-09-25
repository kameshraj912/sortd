import Testing
import Foundation
@testable import Spend

/// TipRules is pure: no Views, no TipKit state, just the eligibility math so
/// it can be pinned before the tips themselves exist. Contract lives in
/// docs/specs/2026-09-25-free-app-overhaul-7-tips.md.
struct TipRulesTests {

    // MARK: add — Home seen twice, no manual purchase yet.

    @Test func addShowsAtTwoHomeVisitsWithNoManualPurchase() {
        #expect(TipRules.add(homeVisits: 2, manualCount: 0, setupShowing: false) == true)
    }

    @Test func addHidesBelowTwoHomeVisits() {
        #expect(TipRules.add(homeVisits: 1, manualCount: 0, setupShowing: false) == false)
    }

    @Test func addHidesOnceAManualPurchaseExists() {
        #expect(TipRules.add(homeVisits: 2, manualCount: 1, setupShowing: false) == false)
    }

    // MARK: applePay — setup done, Shortcut never reached the app.

    @Test func applePayShowsWhenSetupDoneAndShortcutNeverReached() {
        #expect(TipRules.applePay(setupDone: true, shortcutReached: false, setupShowing: false) == true)
    }

    @Test func applePayHidesWhenSetupNotDone() {
        #expect(TipRules.applePay(setupDone: false, shortcutReached: false, setupShowing: false) == false)
    }

    @Test func applePayHidesOnceShortcutReachedTheApp() {
        #expect(TipRules.applePay(setupDone: true, shortcutReached: true, setupShowing: false) == false)
    }

    // MARK: swipe — 3rd Activity visit, 5+ purchases, boundary at 2 vs 3 visits.

    @Test func swipeShowsAtThreeVisitsFivePurchasesUnused() {
        #expect(TipRules.swipe(activityVisits: 3, purchases: 5, swipeUsed: false, setupShowing: false) == true)
    }

    @Test func swipeHidesAtTwoVisits() {
        #expect(TipRules.swipe(activityVisits: 2, purchases: 5, swipeUsed: false, setupShowing: false) == false)
    }

    @Test func swipeHidesBelowFivePurchases() {
        #expect(TipRules.swipe(activityVisits: 3, purchases: 4, swipeUsed: false, setupShowing: false) == false)
    }

    @Test func swipeHidesOnceUsed() {
        #expect(TipRules.swipe(activityVisits: 3, purchases: 5, swipeUsed: true, setupShowing: false) == false)
    }

    // MARK: search — 20+ purchases, boundary at 19 vs 20.

    @Test func searchHidesAtNineteenPurchases() {
        #expect(TipRules.search(purchases: 19, searchUsed: false, setupShowing: false) == false)
    }

    @Test func searchShowsAtTwentyPurchases() {
        #expect(TipRules.search(purchases: 20, searchUsed: false, setupShowing: false) == true)
    }

    @Test func searchHidesOnceUsed() {
        #expect(TipRules.search(purchases: 20, searchUsed: true, setupShowing: false) == false)
    }

    // MARK: insights — first visit with 7+ days of data, boundary at 6 vs 7 days.

    @Test func insightsHidesAtSixDaysOfData() {
        #expect(TipRules.insights(daysOfData: 6, chipsUsed: false, setupShowing: false) == false)
    }

    @Test func insightsShowsAtSevenDaysOfData() {
        #expect(TipRules.insights(daysOfData: 7, chipsUsed: false, setupShowing: false) == true)
    }

    @Test func insightsHidesOnceChipsUsed() {
        #expect(TipRules.insights(daysOfData: 7, chipsUsed: true, setupShowing: false) == false)
    }

    // MARK: month — second calendar month of data, stops when month is changed.

    @Test func monthShowsAtSecondCalendarMonthOfData() {
        #expect(TipRules.month(calendarMonthsOfData: 2, monthChanged: false, setupShowing: false) == true)
    }

    @Test func monthHidesAtOneCalendarMonthOfData() {
        #expect(TipRules.month(calendarMonthsOfData: 1, monthChanged: false, setupShowing: false) == false)
    }

    @Test func monthHidesOnceMonthChanged() {
        #expect(TipRules.month(calendarMonthsOfData: 2, monthChanged: true, setupShowing: false) == false)
    }

    // MARK: setupShowing forces every rule to false, regardless of the rest.

    @Test func setupShowingForcesAddFalse() {
        #expect(TipRules.add(homeVisits: 5, manualCount: 0, setupShowing: true) == false)
    }

    @Test func setupShowingForcesApplePayFalse() {
        #expect(TipRules.applePay(setupDone: true, shortcutReached: false, setupShowing: true) == false)
    }

    @Test func setupShowingForcesSwipeFalse() {
        #expect(TipRules.swipe(activityVisits: 10, purchases: 50, swipeUsed: false, setupShowing: true) == false)
    }

    @Test func setupShowingForcesSearchFalse() {
        #expect(TipRules.search(purchases: 100, searchUsed: false, setupShowing: true) == false)
    }

    @Test func setupShowingForcesInsightsFalse() {
        #expect(TipRules.insights(daysOfData: 30, chipsUsed: false, setupShowing: true) == false)
    }

    @Test func setupShowingForcesMonthFalse() {
        #expect(TipRules.month(calendarMonthsOfData: 5, monthChanged: false, setupShowing: true) == false)
    }

    // MARK: onlyOne — the first eligible candidate on a screen, else nil.

    @Test func onlyOnePicksTheFirstEligibleCandidate() {
        #expect(TipRules.onlyOne([false, true, true]) == 1)
    }

    @Test func onlyOneIsNilWhenNoneAreEligible() {
        #expect(TipRules.onlyOne([false, false]) == nil)
    }

    // MARK: "Show tips again" — the reset spy, through the static var.

    @Test func showTipsAgainCallsResetDatastoreOnce() {
        var calls = 0
        let original = TipRules.resetDatastore
        TipRules.resetDatastore = { calls += 1 }
        defer { TipRules.resetDatastore = original }

        TipRules.resetDatastore()

        #expect(calls == 1)
    }
}

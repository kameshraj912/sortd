import Testing
import Foundation
@testable import Spend

/// TipState turns the counters into one eligibility per tip. These tests
/// give it a fresh UserDefaults suite and a spy in place of TipKit, so
/// nothing here opens TipKit's store. Serialized: the state is static.
@Suite(.serialized)
@MainActor
struct TipStateTests {
    /// Runs `body` against a throwaway defaults suite and an `apply` spy,
    /// then puts everything back.
    private func withFreshState(_ body: (UserDefaults, () -> TipState.Eligibility?) throws -> Void) rethrows {
        let name = "TipStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let originalDefaults = TipState.defaults
        let originalApply = TipState.apply
        let originalSetup = TipState.setupShowing
        var last: TipState.Eligibility?
        TipState.defaults = defaults
        TipState.apply = { last = $0 }
        TipState.setupShowing = false
        TipState.update(figures: .empty)
        defer {
            TipState.defaults = originalDefaults
            TipState.apply = originalApply
            TipState.setupShowing = originalSetup
            defaults.removePersistentDomain(forName: name)
        }
        try body(defaults, { last })
    }

    private func pastFirstSession(_ d: UserDefaults) {
        d.set(true, forKey: TipState.firstSessionEndedKey)
        d.set(true, forKey: OnboardingView.doneKey)
    }

    // MARK: MUST-FIX: the Apple Pay tip only when its row is on screen.

    @Test func cashUserWithSetupDoneNeverGetsTheApplePayTipSoMonthCanShow() {
        withFreshState { d, last in
            pastFirstSession(d)
            d.set(SetupProfile.Payment.cash.rawValue, forKey: SetupProfile.paymentKey)
            d.set(2, forKey: TipState.homeVisitsKey)
            TipState.update(figures: TipState.Figures(manualCount: 1, purchases: 10, daysOfData: 40, monthsOfData: 2))
            let e = try! #require(last())
            #expect(e.applePay == false)
            #expect(e.month == true)
            #expect(TipRules.onlyOne([e.applePay, e.month]) == 1)
        }
    }

    @Test func applePayTipShowsForACardUserWhoseRowIsOnScreen() {
        withFreshState { d, last in
            pastFirstSession(d)
            d.set(SetupProfile.Payment.applePay.rawValue, forKey: SetupProfile.paymentKey)
            TipState.update(figures: TipState.Figures(manualCount: 1, purchases: 3, daysOfData: 3, monthsOfData: 1))
            #expect(last()?.applePay == true)
        }
    }

    @Test func applePayTipHidesWhenTheFinishSetupCardIsHidden() {
        withFreshState { d, last in
            pastFirstSession(d)
            d.set(SetupProfile.Payment.applePay.rawValue, forKey: SetupProfile.paymentKey)
            d.set(true, forKey: SetupChecklist.hiddenKey)
            TipState.update(figures: TipState.Figures(manualCount: 1, purchases: 3, daysOfData: 3, monthsOfData: 1))
            #expect(last()?.applePay == false)
        }
    }

    @Test func applePayTipHidesWhileSampleDataIsIn() {
        withFreshState { d, last in
            pastFirstSession(d)
            d.set(SetupProfile.Payment.applePay.rawValue, forKey: SetupProfile.paymentKey)
            d.set(true, forKey: DemoData.activeKey)
            TipState.update(figures: TipState.Figures(manualCount: 1, purchases: 3, daysOfData: 3, monthsOfData: 1))
            #expect(last()?.applePay == false)
        }
    }

    // MARK: Sample data never counts.

    @Test func sampleRowsAreLeftOutOfEveryFigure() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        let old = cal.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let rows: [TipState.Figures.Row] = (0..<25).map { _ in .init(date: old, manual: true, sample: true) }
            + [.init(date: now, manual: true, sample: false), .init(date: now, manual: false, sample: false)]
        let f = TipState.Figures(rows: rows, now: now, calendar: cal)
        #expect(f.manualCount == 1)
        #expect(f.purchases == 2)
        #expect(f.daysOfData == 1)
        #expect(f.monthsOfData == 1)
    }

    @Test func figuresCountDaysAndMonthsFromTheEarliestRealRow() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        let earlier = cal.date(from: DateComponents(year: 2026, month: 8, day: 30))!
        let f = TipState.Figures(rows: [.init(date: earlier, manual: false, sample: false),
                                        .init(date: now, manual: false, sample: false)], now: now, calendar: cal)
        #expect(f.daysOfData == 27)
        #expect(f.monthsOfData == 2)
    }

    // MARK: A junk date does not make "7+ days of data" true on day one.

    @Test func aPurchaseDatedYearsAgoDoesNotCountAsDaysOfData() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 4))!
        let junk = cal.date(from: DateComponents(year: 2008, month: 1, day: 1))!
        let f = TipState.Figures(rows: [.init(date: junk, manual: false, sample: false),
                                        .init(date: now, manual: false, sample: false)], now: now, calendar: cal)
        #expect(f.daysOfData == 1)
        #expect(f.monthsOfData == 1)
        #expect(f.purchases == 2)
        #expect(TipRules.insights(daysOfData: f.daysOfData, chipsUsed: false, setupShowing: false) == false)
    }

    @Test func aYearOfImportedHistoryStillCounts() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 4))!
        let lastYear = cal.date(from: DateComponents(year: 2025, month: 11, day: 1))!
        let f = TipState.Figures(rows: [.init(date: lastYear, manual: false, sample: false)], now: now, calendar: cal)
        #expect(f.daysOfData > 300)
        #expect(f.monthsOfData == 1)
    }

    @Test func onlyJunkDatesMeansNoData() {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 4))!
        let junk = cal.date(from: DateComponents(year: 2008, month: 1, day: 1))!
        let f = TipState.Figures(rows: [.init(date: junk, manual: false, sample: false)], now: now, calendar: cal)
        #expect(f.daysOfData == 0)
        #expect(f.monthsOfData == 0)
    }

    // MARK: Visits.

    @Test func homeVisitsAreNotCountedWhileSetupIsShowing() {
        withFreshState { d, _ in
            TipState.setupShowing = true
            TipState.visited(.home)
            #expect(d.integer(forKey: TipState.homeVisitsKey) == 0)
            TipState.setupShowing = false
            TipState.visited(.home)
            TipState.visited(.home)
            #expect(d.integer(forKey: TipState.homeVisitsKey) == 2)
        }
    }

    @Test func onlyHomeAndActivityVisitsAreCounted() {
        withFreshState { d, _ in
            TipState.visited(.activity)
            TipState.visited(.insights)
            TipState.visited(.search)
            #expect(d.integer(forKey: TipState.activityVisitsKey) == 1)
            #expect(d.integer(forKey: TipState.homeVisitsKey) == 0)
        }
    }

    // MARK: Analytics: tip_shown and tip_used once per tip id.

    @Test func shownIsRecordedOncePerTip() {
        withFreshState { _, _ in
            #expect(TipState.recordShown("search") == true)
            #expect(TipState.recordShown("search") == false)
            #expect(TipState.recordShown("month") == true)
        }
    }

    @Test func usedIsRecordedOnceAndOnlyAfterShown() {
        withFreshState { _, _ in
            #expect(TipState.recordUsed("search") == false, "never shown")
            _ = TipState.recordShown("search")
            #expect(TipState.recordUsed("search") == true)
            #expect(TipState.recordUsed("search") == false, "a second keystroke")
        }
    }

    // MARK: "Show tips again" when TipKit's reset fails.

    @Test func showTipsAgainStillClearsCountersAndDefersTheResetWhenTipKitFails() {
        withFreshState { d, _ in
            let original = TipRules.tryResetDatastore
            TipRules.tryResetDatastore = { false }
            defer { TipRules.tryResetDatastore = original }
            d.set(true, forKey: TipState.searchUsedKey)
            d.set(["search"], forKey: TipState.shownKey)

            #expect(TipState.showTipsAgain() == false)

            #expect(d.bool(forKey: TipState.searchUsedKey) == false)
            #expect(d.stringArray(forKey: TipState.shownKey) == nil)
            #expect(d.bool(forKey: TipState.pendingResetKey) == true)
        }
    }

    @Test func showTipsAgainNeedsNoRelaunchWhenTipKitResets() {
        withFreshState { d, _ in
            let original = TipRules.tryResetDatastore
            TipRules.tryResetDatastore = { true }
            defer { TipRules.tryResetDatastore = original }
            #expect(TipState.showTipsAgain() == true)
            #expect(d.bool(forKey: TipState.pendingResetKey) == false)
        }
    }

    @Test func aPendingResetRunsOnceAtTheNextLaunch() {
        withFreshState { d, _ in
            var calls = 0
            let original = TipRules.tryResetDatastore
            TipRules.tryResetDatastore = { calls += 1; return true }
            defer { TipRules.tryResetDatastore = original }
            TipState.resetAtNextLaunch()
            TipState.applyPendingReset()
            TipState.applyPendingReset()
            #expect(calls == 1)
            #expect(d.bool(forKey: TipState.pendingResetKey) == false)
        }
    }
}

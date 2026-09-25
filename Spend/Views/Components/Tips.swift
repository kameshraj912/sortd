import SwiftUI
import TipKit

/// In-app tips (overhaul sub-spec 7). Six TipKit tips that appear one at a
/// time, at the moment a feature matters: never as a tour, never during
/// setup, never in the first-launch session.
///
/// Three parts, each on its own:
/// - `TipCopy`: the six lines (tested for tone and length).
/// - `TipRules`: the eligibility maths as pure functions (tested).
/// - `TipState`: the counters behind the rules, in UserDefaults, and the one
///   `refresh()` that turns them into each tip's `eligible` parameter.
///
/// TipKit itself does the rest: shows a tip once its rule is true, keeps it
/// up until it is closed or invalidated, and allows one new tip a day
/// (`displayFrequency(.daily)` in `SpendApp`).

// MARK: - Copy

/// One tip's words. Plain, one sentence, no "Pro". The id is the analytics
/// key (`tip_shown` / `tip_used`).
nonisolated struct TipCopy: Identifiable, Sendable {
    let id: String
    let title: String
    let message: String
    let symbol: String

    static let add = TipCopy(id: "add", title: "Add cash or anything Apple Pay missed",
                             message: "Tap the plus button to log a purchase by hand.", symbol: "plus.circle")
    static let applePay = TipCopy(id: "apple_pay", title: "Log Apple Pay by itself",
                                  message: "Set up the Shortcut once and every tap lands here on its own.",
                                  symbol: "wave.3.right")
    static let swipe = TipCopy(id: "swipe", title: "Swipe left to change a category or delete",
                               message: "Swipe a purchase to change its category or delete it.",
                               symbol: "hand.draw")
    static let search = TipCopy(id: "search", title: "Search by shop, category or note",
                                message: "Type a shop, a category or a word from a note to find any purchase.",
                                symbol: "magnifyingglass")
    static let insights = TipCopy(id: "insights", title: "See this month next to last",
                                  message: "Tap 1W, 1M or 3M to compare this period with the one before.",
                                  symbol: "chart.xyaxis.line")
    static let month = TipCopy(id: "month", title: "Tap the month to look back",
                               message: "Tap the month at the top to see any of the last 12 months.",
                               symbol: "calendar")

    static let all: [TipCopy] = [add, applePay, swipe, search, insights, month]
}

// MARK: - Rules

/// When each tip may show, as pure functions of the counters. `setupShowing`
/// wins over everything: no tip while setup is on screen.
enum TipRules {
    /// Home seen twice, no purchase added by hand yet.
    static func add(homeVisits: Int, manualCount: Int, setupShowing: Bool) -> Bool {
        !setupShowing && homeVisits >= 2 && manualCount == 0
    }

    /// Setup done, the Shortcut has never reached the app.
    static func applePay(setupDone: Bool, shortcutReached: Bool, setupShowing: Bool) -> Bool {
        !setupShowing && setupDone && !shortcutReached
    }

    /// Third Activity visit with five or more purchases, and no swipe yet.
    static func swipe(activityVisits: Int, purchases: Int, swipeUsed: Bool, setupShowing: Bool) -> Bool {
        !setupShowing && activityVisits >= 3 && purchases >= 5 && !swipeUsed
    }

    /// Twenty or more purchases, and no search run yet.
    static func search(purchases: Int, searchUsed: Bool, setupShowing: Bool) -> Bool {
        !setupShowing && purchases >= 20 && !searchUsed
    }

    /// Seven or more days of data, and the period chips never tapped.
    static func insights(daysOfData: Int, chipsUsed: Bool, setupShowing: Bool) -> Bool {
        !setupShowing && daysOfData >= 7 && !chipsUsed
    }

    /// Data in a second calendar month, and the month never changed.
    static func month(calendarMonthsOfData: Int, monthChanged: Bool, setupShowing: Bool) -> Bool {
        !setupShowing && calendarMonthsOfData >= 2 && !monthChanged
    }

    /// One tip per screen: the index of the first eligible candidate, or nil.
    static func onlyOne(_ candidates: [Bool]) -> Int? {
        candidates.firstIndex(of: true)
    }

    /// "Show tips again" and Delete All Data. A static var so a test can
    /// spy on it without touching TipKit's store.
    static var resetDatastore: () -> Void = {
        do { try Tips.resetDatastore() } catch { log.error("tips: reset failed: \(error.localizedDescription)") }
    }

    /// Calendar days from the earliest purchase to today, both included.
    /// No purchases: 0.
    static func daysOfData(from earliest: Date?, to now: Date, calendar: Calendar) -> Int {
        guard let earliest else { return 0 }
        let start = calendar.startOfDay(for: earliest)
        let end = calendar.startOfDay(for: now)
        guard start <= end else { return 1 }
        return (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
    }

    /// How many different calendar months the purchases fall in.
    static func calendarMonths(of dates: [Date], calendar: Calendar) -> Int {
        Set(dates.map { calendar.dateComponents([.year, .month], from: $0) }).count
    }
}

// MARK: - The tips

/// Each tip has one rule: its `eligible` parameter, set by `TipState.refresh()`.
/// That keeps the maths in `TipRules` (one place, tested) and leaves TipKit
/// the showing, closing and once-a-day pacing.

nonisolated struct AddTip: Tip {
    @Parameter static var eligible: Bool = false
    var id: String { TipCopy.add.id }
    var title: Text { Text(TipCopy.add.title) }
    var message: Text? { Text(TipCopy.add.message) }
    var image: Image? { Image(systemName: TipCopy.add.symbol) }
    var rules: [Rule] { #Rule(Self.$eligible) { $0 == true } }
}

nonisolated struct ApplePayTip: Tip {
    @Parameter static var eligible: Bool = false
    var id: String { TipCopy.applePay.id }
    var title: Text { Text(TipCopy.applePay.title) }
    var message: Text? { Text(TipCopy.applePay.message) }
    var image: Image? { Image(systemName: TipCopy.applePay.symbol) }
    var rules: [Rule] { #Rule(Self.$eligible) { $0 == true } }
}

nonisolated struct SwipeTip: Tip {
    @Parameter static var eligible: Bool = false
    var id: String { TipCopy.swipe.id }
    var title: Text { Text(TipCopy.swipe.title) }
    var message: Text? { Text(TipCopy.swipe.message) }
    var image: Image? { Image(systemName: TipCopy.swipe.symbol) }
    var rules: [Rule] { #Rule(Self.$eligible) { $0 == true } }
}

nonisolated struct SearchTip: Tip {
    @Parameter static var eligible: Bool = false
    var id: String { TipCopy.search.id }
    var title: Text { Text(TipCopy.search.title) }
    var message: Text? { Text(TipCopy.search.message) }
    var image: Image? { Image(systemName: TipCopy.search.symbol) }
    var rules: [Rule] { #Rule(Self.$eligible) { $0 == true } }
}

nonisolated struct InsightsTip: Tip {
    @Parameter static var eligible: Bool = false
    var id: String { TipCopy.insights.id }
    var title: Text { Text(TipCopy.insights.title) }
    var message: Text? { Text(TipCopy.insights.message) }
    var image: Image? { Image(systemName: TipCopy.insights.symbol) }
    var rules: [Rule] { #Rule(Self.$eligible) { $0 == true } }
}

nonisolated struct MonthTip: Tip {
    @Parameter static var eligible: Bool = false
    var id: String { TipCopy.month.id }
    var title: Text { Text(TipCopy.month.title) }
    var message: Text? { Text(TipCopy.month.message) }
    var image: Image? { Image(systemName: TipCopy.month.symbol) }
    var rules: [Rule] { #Rule(Self.$eligible) { $0 == true } }
}

// MARK: - State

/// The counters and flags behind the rules, in UserDefaults, and the
/// purchase figures the screens hand over from their `@Query`. Every change
/// ends in `refresh()`, which writes each tip's `eligible` parameter so
/// that at most one tip per screen is true.
enum TipState {
    static let homeVisitsKey = "tips.homeVisits"
    static let activityVisitsKey = "tips.activityVisits"
    static let searchUsedKey = "tips.searchUsed"
    static let swipeUsedKey = "tips.swipeUsed"
    static let chipsUsedKey = "tips.chipsUsed"
    static let monthChangedKey = "tips.monthChanged"
    /// When this install first ran a build with tips.
    static let firstLaunchAtKey = "tips.firstLaunchAt"
    /// Set on the second launch, or ten minutes into the first.
    static let firstSessionEndedKey = "tips.firstLaunchSessionEnded"
    /// Ids of tips TipKit has put on screen, for `tip_used` to be honest.
    static let shownKey = "tips.shown"
    /// "Show tips again" also resets before the next `Tips.configure`.
    static let pendingResetKey = "tips.pendingReset"
    static let firstSessionLength: TimeInterval = 10 * 60

    /// True while setup is on screen. `RootView` keeps it up to date.
    static var setupShowing = false {
        didSet { if setupShowing != oldValue { refresh() } }
    }

    // Figures from the store, cached by the screens that hold a @Query.
    private(set) static var manualCount = 0
    private(set) static var purchases = 0
    private(set) static var daysOfData = 0
    private(set) static var monthsOfData = 0

    // MARK: Launch

    /// Once per launch, before any screen. The first launch of a build with
    /// tips starts the first session, unless setup was already done (an
    /// install from before tips existed is past its first session).
    static func launched(setupDone: Bool, now: Date = .now) {
        let d = UserDefaults.standard
        if d.object(forKey: firstLaunchAtKey) == nil {
            d.set(now, forKey: firstLaunchAtKey)
            if setupDone { d.set(true, forKey: firstSessionEndedKey) }
        } else {
            d.set(true, forKey: firstSessionEndedKey)
        }
    }

    /// Before `Tips.configure`: a reset asked for while the store was open.
    static func applyPendingReset() {
        guard UserDefaults.standard.bool(forKey: pendingResetKey) else { return }
        UserDefaults.standard.removeObject(forKey: pendingResetKey)
        TipRules.resetDatastore()
    }

    #if DEBUG
    /// SPEND_TIPS_NOW=1: skip the first session and the visit counts, so a
    /// tip shows on the first screen. The real one-per-screen rules still apply.
    static func forceNow() {
        let d = UserDefaults.standard
        d.set(true, forKey: firstSessionEndedKey)
        d.set(2, forKey: homeVisitsKey)
        d.set(3, forKey: activityVisitsKey)
        TipRules.resetDatastore()
    }
    #endif

    static var firstSessionEnded: Bool {
        let d = UserDefaults.standard
        if d.bool(forKey: firstSessionEndedKey) { return true }
        guard let at = d.object(forKey: firstLaunchAtKey) as? Date,
              Date.now.timeIntervalSince(at) >= firstSessionLength else { return false }
        d.set(true, forKey: firstSessionEndedKey)
        return true
    }

    // MARK: Inputs

    /// The figures the rules need, from every purchase. Sample data never
    /// counts as a purchase added by hand.
    static func update(from transactions: [Transaction]) {
        manualCount = transactions.filter { $0.source == .manual && $0.note != DemoData.marker }.count
        purchases = transactions.count
        let dates = transactions.map(\.date)
        daysOfData = TipRules.daysOfData(from: dates.min(), to: .now, calendar: .current)
        monthsOfData = TipRules.calendarMonths(of: dates, calendar: .current)
        refresh()
    }

    static func visitedHome() { bump(homeVisitsKey) }
    static func visitedActivity() { bump(activityVisitsKey) }

    // The thing the tip was about has been done: the tip is over.
    static func searchUsed() { done(searchUsedKey, SearchTip()) }
    static func swipeUsed() { done(swipeUsedKey, SwipeTip()) }
    static func chipsUsed() { done(chipsUsedKey, InsightsTip()) }
    static func monthChanged() { done(monthChangedKey, MonthTip()) }
    static func manualPurchaseAdded() {
        manualCount += 1
        used(AddTip())
        refresh()
    }

    /// TipKit has put this tip on screen (from `shouldDisplayUpdates`).
    static func shown(_ id: String) {
        var ids = UserDefaults.standard.stringArray(forKey: shownKey) ?? []
        guard !ids.contains(id) else { return }
        ids.append(id)
        UserDefaults.standard.set(ids, forKey: shownKey)
        Analytics.shared.track(.tipShown, ["id": .string(id)])
    }

    /// Settings › Help. TipKit forgets what was shown and closed; the "done"
    /// flags go too, so a tip about a thing already done can show once more.
    /// Visit counts stay: the tips are for people who have looked around.
    static func showTipsAgain() {
        let d = UserDefaults.standard
        for key in [searchUsedKey, swipeUsedKey, chipsUsedKey, monthChangedKey, shownKey] {
            d.removeObject(forKey: key)
        }
        d.set(true, forKey: pendingResetKey)
        TipRules.resetDatastore()
        refresh()
    }

    // MARK: Refresh

    /// Turns the counters into each tip's `eligible` parameter, one tip per
    /// screen at most: Home (add, Apple Pay, month), Activity (swipe,
    /// search), Insights.
    static func refresh() {
        let d = UserDefaults.standard
        let past = firstSessionEnded
        let setup = setupShowing
        if LogPurchaseIntent.shortcutHasReachedApp { used(ApplePayTip()) }

        let add = past && TipRules.add(homeVisits: d.integer(forKey: homeVisitsKey),
                                       manualCount: manualCount, setupShowing: setup)
        let applePay = past && TipRules.applePay(setupDone: d.bool(forKey: OnboardingView.doneKey),
                                                 shortcutReached: LogPurchaseIntent.shortcutHasReachedApp,
                                                 setupShowing: setup)
        let month = past && TipRules.month(calendarMonthsOfData: monthsOfData,
                                           monthChanged: d.bool(forKey: monthChangedKey), setupShowing: setup)
        let swipe = past && TipRules.swipe(activityVisits: d.integer(forKey: activityVisitsKey), purchases: purchases,
                                           swipeUsed: d.bool(forKey: swipeUsedKey), setupShowing: setup)
        let search = past && TipRules.search(purchases: purchases, searchUsed: d.bool(forKey: searchUsedKey),
                                             setupShowing: setup)
        let insights = past && TipRules.insights(daysOfData: daysOfData, chipsUsed: d.bool(forKey: chipsUsedKey),
                                                 setupShowing: setup)

        let home = TipRules.onlyOne([add && open(AddTip()), applePay && open(ApplePayTip()), month && open(MonthTip())])
        set(&AddTip.eligible, home == 0)
        set(&ApplePayTip.eligible, home == 1)
        set(&MonthTip.eligible, home == 2)
        let activity = TipRules.onlyOne([swipe && open(SwipeTip()), search && open(SearchTip())])
        set(&SwipeTip.eligible, activity == 0)
        set(&SearchTip.eligible, activity == 1)
        set(&InsightsTip.eligible, insights && open(InsightsTip()))
    }

    // MARK: Helpers

    private static func bump(_ key: String) {
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: key) + 1, forKey: key)
        refresh()
    }

    private static func done(_ key: String, _ tip: some Tip) {
        UserDefaults.standard.set(true, forKey: key)
        used(tip)
        refresh()
    }

    /// Invalidates the tip because its action was performed. `tip_used`
    /// only when the tip had been on screen, and only once.
    private static func used(_ tip: some Tip) {
        guard open(tip) else { return }
        tip.invalidate(reason: .actionPerformed)
        if (UserDefaults.standard.stringArray(forKey: shownKey) ?? []).contains(tip.id) {
            Analytics.shared.track(.tipUsed, ["id": .string(tip.id)])
        }
    }

    /// Not yet closed or invalidated.
    private static func open(_ tip: some Tip) -> Bool {
        if case .invalidated = tip.status { return false }
        return true
    }

    /// A parameter write goes to TipKit's store: only when it changes.
    private static func set(_ parameter: inout Bool, _ value: Bool) {
        if parameter != value { parameter = value }
    }
}

// MARK: - Views

/// A popover tip that records `tip_shown` when TipKit presents it. `nil`
/// attaches nothing.
extension View {
    func sortdTip(_ tip: (any Tip)?, arrowEdge: Edge? = nil) -> some View {
        modifier(SortdPopoverTip(tip: tip, arrowEdge: arrowEdge))
    }
}

private struct SortdPopoverTip: ViewModifier {
    let tip: (any Tip)?
    let arrowEdge: Edge?

    func body(content: Content) -> some View {
        content
            .popoverTip(tip, arrowEdge: arrowEdge)
            .modifier(TipShownReporter(tip: tip))
    }
}

/// An inline tip card that records `tip_shown` when TipKit presents it.
struct SortdTipView: View {
    let tip: any Tip

    var body: some View {
        TipView(tip)
            .tipCornerRadius(20)
            .modifier(TipShownReporter(tip: tip))
    }
}

/// `shouldDisplay` is true when the tip's rule holds and the daily pacing
/// allows it: with the tip anchored on this screen, that is "shown".
private struct TipShownReporter: ViewModifier {
    let tip: (any Tip)?

    func body(content: Content) -> some View {
        content.task(id: tip?.id) {
            guard let tip else { return }
            if tip.shouldDisplay { TipState.shown(tip.id) }
            for await on in tip.shouldDisplayUpdates where on {
                TipState.shown(tip.id)
            }
        }
    }
}

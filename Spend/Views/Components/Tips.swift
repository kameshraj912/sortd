import SwiftUI
import TipKit
import Observation

/// In-app tips (overhaul sub-spec 7). Five TipKit tips that appear one at a
/// time, at the moment a feature matters: never as a tour, never during
/// setup, never in the first-launch session, and never while the app intro
/// (`docs/specs/2026-09-25-app-intro.md`) is up — it teaches + instead of
/// the sixth tip, which is gone.
///
/// Four parts, each on its own:
/// - `TipCopy`: the five lines (tested for tone and length).
/// - `TipRules`: the eligibility maths as pure functions (tested).
/// - `TipState`: the counters behind the rules, in UserDefaults, and the one
///   `refresh()` that turns them into an `Eligibility` (tested with a
///   throwaway defaults suite and a spy in place of TipKit).
/// - `TipVisibility`: which tips TipKit is showing right now, for the
///   inline cards to come and go with.
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

    static let applePay = TipCopy(id: "apple_pay", title: "Log Apple Pay by itself",
                                  message: "Set it up once in Shortcuts and every tap lands here on its own.",
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

    static let all: [TipCopy] = [applePay, swipe, search, insights, month]
}

// MARK: - Rules

/// When each tip may show, as pure functions of the counters. `setupShowing`
/// wins over everything: no tip while setup is on screen.
enum TipRules {
    /// Setup done, the Shortcut has never reached the app, and the Apple Pay
    /// row is on screen (a card user, the Finish Setup card not hidden, no
    /// sample data). A cash user gets the widget row instead.
    static func applePay(setupDone: Bool, shortcutReached: Bool, rowShowing: Bool, setupShowing: Bool) -> Bool {
        !setupShowing && setupDone && !shortcutReached && rowShowing
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

    /// TipKit's reset, as a Bool: it can fail while the store is open.
    /// A static var so a test can stand in for TipKit.
    static var tryResetDatastore: () -> Bool = {
        do {
            try Tips.resetDatastore()
            return true
        } catch {
            log.error("tips: reset failed: \(error.localizedDescription)")
            return false
        }
    }

    /// The same reset with no answer, for callers that cannot act on one.
    static var resetDatastore: () -> Void = { _ = TipRules.tryResetDatastore() }

    /// The oldest a purchase can be and still count towards "days of data"
    /// and "months of data". Real imported history sits inside this.
    static let historyWindowDays = 400

    static func countsAsHistory(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        guard let oldest = calendar.date(byAdding: .day, value: -historyWindowDays, to: now) else { return true }
        return date >= oldest
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

/// Each tip has one rule: its `eligible` parameter, set by `TipState`.
/// That keeps the maths in `TipRules` (one place, tested) and leaves TipKit
/// the showing, closing and once-a-day pacing.

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
/// ends in `refresh()`, which works out an `Eligibility` and hands it to
/// `apply` (TipKit in the app, a spy in tests).
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
    /// Ids of tips TipKit has put on screen: `tip_shown` once each.
    static let shownKey = "tips.shown"
    /// Ids whose action was done after they were shown: `tip_used` once each.
    static let usedKey = "tips.used"
    /// A reset TipKit could not do while open, for the next launch.
    static let pendingResetKey = "tips.pendingReset"
    static let firstSessionLength: TimeInterval = 10 * 60

    /// Where the counters live. Tests point this at a throwaway suite.
    static var defaults: UserDefaults = .standard
    /// Where an eligibility goes. TipKit in the app; a spy in tests.
    static var apply: @MainActor (Eligibility) -> Void = { applyToTipKit($0) }

    /// True while setup is on screen. `RootView` keeps it up to date.
    static var setupShowing = false {
        didSet { if setupShowing != oldValue { refresh() } }
    }

    /// True while the app intro is on screen. `RootView` keeps it up to
    /// date, the same way it does `setupShowing`: no tip fights the intro
    /// for the same spot on Home or Activity.
    static var introShowing = false {
        didSet { if introShowing != oldValue { refresh() } }
    }

    /// The figures from the store, as the screens last reported them.
    private(set) static var figures = Figures.empty

    /// What the rules need from the purchases. Sample data never counts.
    struct Figures: Equatable, Sendable {
        var manualCount: Int
        var purchases: Int
        var daysOfData: Int
        var monthsOfData: Int

        static let empty = Figures(manualCount: 0, purchases: 0, daysOfData: 0, monthsOfData: 0)

        struct Row: Sendable {
            let date: Date
            let manual: Bool
            let sample: Bool
        }

        init(manualCount: Int, purchases: Int, daysOfData: Int, monthsOfData: Int) {
            self.manualCount = manualCount
            self.purchases = purchases
            self.daysOfData = daysOfData
            self.monthsOfData = monthsOfData
        }

        init(rows: [Row], now: Date, calendar: Calendar) {
            let real = rows.filter { !$0.sample }
            manualCount = real.filter(\.manual).count
            purchases = real.count
            // A purchase dated years back (a bad import, a typo) must not make
            // a new install look like it has months of history.
            let dates = real.map(\.date).filter { TipRules.countsAsHistory($0, now: now, calendar: calendar) }
            daysOfData = TipRules.daysOfData(from: dates.min(), to: now, calendar: calendar)
            monthsOfData = TipRules.calendarMonths(of: dates, calendar: calendar)
        }
    }

    /// Each rule's answer. Which one a screen shows is decided when it is
    /// applied (a tip already closed gives way to the next).
    struct Eligibility: Equatable, Sendable {
        var applePay = false
        var month = false
        var swipe = false
        var search = false
        var insights = false
    }

    // MARK: Launch

    /// Once per launch, before any screen. The first launch of a build with
    /// tips starts the first session, unless setup was already done (an
    /// install from before tips existed is past its first session).
    static func launched(setupDone: Bool, now: Date = .now) {
        if defaults.object(forKey: firstLaunchAtKey) == nil {
            defaults.set(now, forKey: firstLaunchAtKey)
            if setupDone { defaults.set(true, forKey: firstSessionEndedKey) }
        } else {
            defaults.set(true, forKey: firstSessionEndedKey)
        }
    }

    /// Delete All Data: TipKit's store is reset at the next launch, before
    /// it opens (a reset while it is open can fail).
    static func resetAtNextLaunch() {
        defaults.set(true, forKey: pendingResetKey)
    }

    /// Before `Tips.configure`. The flag stays if the reset fails again.
    static func applyPendingReset() {
        guard defaults.bool(forKey: pendingResetKey) else { return }
        if TipRules.tryResetDatastore() { defaults.removeObject(forKey: pendingResetKey) }
    }

    #if DEBUG
    /// SPEND_TIPS_NOW=1: skip the first session and the visit counts, so a
    /// tip shows on the first screen. The real one-per-screen rules still apply.
    static func forceNow() {
        defaults.set(true, forKey: firstSessionEndedKey)
        defaults.set(2, forKey: homeVisitsKey)
        defaults.set(3, forKey: activityVisitsKey)
        _ = TipRules.tryResetDatastore()
    }
    #endif

    static var firstSessionEnded: Bool {
        if defaults.bool(forKey: firstSessionEndedKey) { return true }
        guard let at = defaults.object(forKey: firstLaunchAtKey) as? Date,
              Date.now.timeIntervalSince(at) >= firstSessionLength else { return false }
        defaults.set(true, forKey: firstSessionEndedKey)
        return true
    }

    // MARK: Inputs

    /// The figures the rules need, from every purchase.
    static func update(from transactions: [Transaction]) {
        let rows = transactions.map {
            Figures.Row(date: $0.date, manual: $0.source == .manual, sample: $0.note == DemoData.marker)
        }
        update(figures: Figures(rows: rows, now: .now, calendar: .current))
    }

    static func update(figures new: Figures) {
        figures = new
        refresh()
    }

    /// A tab opened from another tab, or the app coming back on it. Not a
    /// return from a pushed detail, and nothing while setup is up.
    static func visited(_ tab: AppTab) {
        guard !setupShowing else { return }
        switch tab {
        case .home: bump(homeVisitsKey)
        case .activity: bump(activityVisitsKey)
        default: break
        }
    }

    // The thing the tip was about has been done: the tip is over.
    static func searchUsed() { done(searchUsedKey, SearchTip()) }
    static func swipeUsed() { done(swipeUsedKey, SwipeTip()) }
    static func chipsUsed() { done(chipsUsedKey, InsightsTip()) }
    static func monthChanged() { done(monthChangedKey, MonthTip()) }
    static func manualPurchaseAdded() {
        figures.manualCount += 1
        refresh()
    }

    /// TipKit has put this tip on screen. True the first time only.
    @discardableResult
    static func recordShown(_ id: String) -> Bool { append(id, to: shownKey) }

    /// The tip's action was done. True once, and only after it was shown.
    @discardableResult
    static func recordUsed(_ id: String) -> Bool {
        guard (defaults.stringArray(forKey: shownKey) ?? []).contains(id) else { return false }
        return append(id, to: usedKey)
    }

    static func shown(_ id: String) {
        if recordShown(id) { Analytics.shared.track(.tipShown, ["id": .string(id)]) }
    }

    /// Settings › Help. TipKit forgets what was shown and closed; the "done"
    /// flags go too, so a tip about a thing already done can show once more.
    /// Visit counts stay: the tips are for people who have looked around.
    /// False when TipKit could not reset now: it will at the next launch.
    @discardableResult
    static func showTipsAgain() -> Bool {
        for key in [searchUsedKey, swipeUsedKey, chipsUsedKey, monthChangedKey, shownKey, usedKey] {
            defaults.removeObject(forKey: key)
        }
        let reset = TipRules.tryResetDatastore()
        if reset { defaults.removeObject(forKey: pendingResetKey) } else { resetAtNextLaunch() }
        refresh()
        return reset
    }

    // MARK: Refresh

    /// Each rule against the counters. Pure apart from reading the defaults.
    static func compute() -> Eligibility {
        let d = defaults
        guard firstSessionEnded, !introShowing else { return Eligibility() }
        let setup = setupShowing
        let shortcutReached = d.object(forKey: LogPurchaseIntent.lastTapAtKey) != nil
        let payment = SetupProfile.Payment(rawValue: d.string(forKey: SetupProfile.paymentKey) ?? "")
        let applePayRow = payment != .cash
            && !d.bool(forKey: SetupChecklist.hiddenKey)
            && !d.bool(forKey: DemoData.activeKey)
        return Eligibility(
            applePay: TipRules.applePay(setupDone: d.bool(forKey: OnboardingView.doneKey),
                                        shortcutReached: shortcutReached, rowShowing: applePayRow, setupShowing: setup),
            month: TipRules.month(calendarMonthsOfData: figures.monthsOfData,
                                  monthChanged: d.bool(forKey: monthChangedKey), setupShowing: setup),
            swipe: TipRules.swipe(activityVisits: d.integer(forKey: activityVisitsKey), purchases: figures.purchases,
                                  swipeUsed: d.bool(forKey: swipeUsedKey), setupShowing: setup),
            search: TipRules.search(purchases: figures.purchases, searchUsed: d.bool(forKey: searchUsedKey),
                                    setupShowing: setup),
            insights: TipRules.insights(daysOfData: figures.daysOfData, chipsUsed: d.bool(forKey: chipsUsedKey),
                                        setupShowing: setup))
    }

    static func refresh() { apply(compute()) }

    /// Writes each tip's `eligible` parameter, one tip per screen at most:
    /// Home (Apple Pay, month), Activity (swipe, search), Insights.
    /// A tip already closed or invalidated gives its place to the next.
    private static func applyToTipKit(_ e: Eligibility) {
        if defaults.object(forKey: LogPurchaseIntent.lastTapAtKey) != nil { used(ApplePayTip()) }
        let home = TipRules.onlyOne([e.applePay && open(ApplePayTip()), e.month && open(MonthTip())])
        set(&ApplePayTip.eligible, home == 0)
        set(&MonthTip.eligible, home == 1)
        let activity = TipRules.onlyOne([e.swipe && open(SwipeTip()), e.search && open(SearchTip())])
        set(&SwipeTip.eligible, activity == 0)
        set(&SearchTip.eligible, activity == 1)
        set(&InsightsTip.eligible, e.insights && open(InsightsTip()))
    }

    // MARK: Helpers

    private static func bump(_ key: String) {
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
        refresh()
    }

    private static func done(_ key: String, _ tip: some Tip) {
        let already = defaults.bool(forKey: key)
        defaults.set(true, forKey: key)
        used(tip)
        if !already { refresh() }
    }

    /// Invalidates the tip because its action was performed. `tip_used`
    /// only when the tip had been on screen, and only once.
    private static func used(_ tip: some Tip) {
        guard open(tip) else { return }
        tip.invalidate(reason: .actionPerformed)
        if recordUsed(tip.id) { Analytics.shared.track(.tipUsed, ["id": .string(tip.id)]) }
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

    /// Adds `id` to the list at `key`. False when it was there already.
    private static func append(_ id: String, to key: String) -> Bool {
        var ids = defaults.stringArray(forKey: key) ?? []
        guard !ids.contains(id) else { return false }
        ids.append(id)
        defaults.set(ids, forKey: key)
        return true
    }
}

// MARK: - Visibility

/// Which tips TipKit would show right now, kept from each tip's
/// `shouldDisplayUpdates`. The inline cards read it so a hidden tip leaves
/// no empty row behind. Started once at launch, after `Tips.configure`.
@MainActor @Observable
final class TipVisibility {
    static let shared = TipVisibility()

    private(set) var showing: Set<String> = []
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let all: [any Tip] = [ApplePayTip(), SwipeTip(), SearchTip(), InsightsTip(), MonthTip()]
        for tip in all {
            Task { @MainActor in
                self.set(tip.id, tip.shouldDisplay)
                for await on in tip.shouldDisplayUpdates { self.set(tip.id, on) }
            }
        }
    }

    func isShowing(_ id: String) -> Bool { showing.contains(id) }

    private func set(_ id: String, _ on: Bool) {
        if on { showing.insert(id) } else { showing.remove(id) }
    }
}

// MARK: - Views

/// A popover tip that records `tip_shown` when TipKit presents it. `nil`
/// attaches nothing. `arrowEdge` is where the arrow sits on the anchor:
/// `.top` puts the tip below it (anchors near the top of the screen),
/// `.bottom` above it (anchors lower down, so the tab bar stays clear).
extension View {
    func sortdTip(_ tip: (any Tip)?, arrowEdge: Edge) -> some View {
        modifier(SortdPopoverTip(tip: tip, arrowEdge: arrowEdge))
    }
}

private struct SortdPopoverTip: ViewModifier {
    let tip: (any Tip)?
    let arrowEdge: Edge
    /// TabView keeps every tab alive, so a tip on another tab's view would be
    /// presented over the tab you are looking at, anchored to nothing. The tip
    /// is only given to TipKit (and only counted as shown) while this view is
    /// on screen.
    @State private var onScreen = false

    func body(content: Content) -> some View {
        let live = onScreen ? tip : nil
        content
            .popoverTip(live, arrowEdge: arrowEdge)
            .modifier(TipShownReporter(tip: live))
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false }
    }
}

/// An inline tip card. Only in the tree while TipKit is showing the tip,
/// so a hidden tip leaves no empty row. Records `tip_shown`.
struct SortdTipView: View {
    let tip: any Tip
    private let visibility = TipVisibility.shared

    var body: some View {
        if visibility.isShowing(tip.id) {
            TipView(tip)
                .tipCornerRadius(20)
                .modifier(TipShownReporter(tip: tip))
        }
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

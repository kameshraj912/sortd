import Foundation

/// The three-step app intro (`docs/specs/2026-09-26-app-intro-v2.md`, option A,
/// "stories"): shown once, right after setup closes (`RootView` sees
/// `setupPresented` turn false), and once for an install that updates past
/// this point. Replayable from Help › "Show the Intro Again".
///
/// Pure: no Views, no UserDefaults reads inside the type itself, so the whole
/// state machine is tested with no simulator. `RootView` keeps one `IntroTour`
/// in `@State`, seeded from `IntroTour.seenKey`, and writes `seen` back to
/// `UserDefaults` itself when it changes.
enum IntroStep: Int, CaseIterable, Equatable, Sendable {
    case add, insights, swipe

    /// Where the app goes while this step is on screen: `RootView` drives
    /// `tab` from this, so the tab bar really switches underneath.
    var tab: AppTab {
        switch self {
        case .add: .home
        case .insights: .insights
        case .swipe: .activity
        }
    }

    /// The one line under the card. Raj's approved wording (26 Sep 2026;
    /// step 3 from 3 Oct 2026, when Activity went back to one list and the
    /// day arrows went).
    var line: String {
        switch self {
        case .add: "Tap + to add cash or anything Apple Pay missed"
        case .insights: "Insights shows where your money goes"
        case .swipe: "Swipe a purchase to change or delete it"
        }
    }

    /// Read before the line, so a VoiceOver user — who can't see the
    /// highlight — still hears what it's pointing at.
    var voiceOverTarget: String {
        switch self {
        case .add: "The plus button, bottom right, adds a purchase."
        case .insights: "The Insights tab, in the tab bar."
        case .swipe: "The newest purchase, on Activity."
        }
    }

    /// "Step 1 of 3. <target>. <line>." — one accessibility element per step.
    var accessibilityLabel: String {
        "Step \(rawValue + 1) of \(IntroStep.allCases.count). \(voiceOverTarget) \(line)."
    }

    /// The motion this step plays once, before it holds. `.none` under
    /// Reduce Motion, where a still ring stands in and the steps cross-fade
    /// instead of animating.
    func motion(reduceMotion: Bool) -> IntroMotion {
        guard !reduceMotion else { return .none }
        switch self {
        case .add: return .tapTwice
        case .insights: return .ringPulse
        case .swipe: return .swipeLeft
        }
    }

    /// How long the step's own animation runs, in seconds, before it holds.
    /// The three add to well under the spec's ~9s budget for the whole tour.
    var motionDuration: TimeInterval {
        switch self {
        case .add: 1.5
        case .insights: 1.0
        case .swipe: 1.0
        }
    }

    /// Every step auto-advances after this long, unless a tap or a hold
    /// changes that (`IntroCountdown`).
    static let stepDuration: TimeInterval = 2.5
}

/// What plays once on a step, before it holds still.
enum IntroMotion: Equatable, Sendable {
    case none, tapTwice, ringPulse, swipeLeft
}

/// A step's auto-advance clock: pure `Date` math, no sleeping, no timer —
/// testable with injected `Date`s. `IntroOverlay` polls `remaining(at:duration:)`
/// on a short interval and advances the tour once it hits zero; a long press
/// pauses it, and lifting resumes from where it paused, not from zero.
struct IntroCountdown: Equatable, Sendable {
    private var stepStartedAt: Date
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0

    init(startedAt: Date) {
        self.stepStartedAt = startedAt
    }

    /// Seconds left in `duration`, clamped to zero. While paused, time
    /// stopped accruing at the moment `pause(at:)` was called.
    func remaining(at now: Date, duration: TimeInterval) -> TimeInterval {
        let clock = pausedAt ?? now
        let elapsed = clock.timeIntervalSince(stepStartedAt) - pausedTotal
        return max(0, duration - elapsed)
    }

    /// Stops the clock at `now`. Calling it again while already paused does
    /// nothing (the first pause moment wins).
    mutating func pause(at now: Date) {
        guard pausedAt == nil else { return }
        pausedAt = now
    }

    /// Restarts the clock from wherever it was paused: the gap between
    /// `pause(at:)` and `resume(at:)` doesn't count against `duration`.
    mutating func resume(at now: Date) {
        guard let pausedAt else { return }
        pausedTotal += now.timeIntervalSince(pausedAt)
        self.pausedAt = nil
    }

    var isPaused: Bool { pausedAt != nil }
}

/// The step machine, plus the seen/replay flags that decide whether it
/// should run at all. A value type: `RootView` keeps one in `@State`;
/// tests build one directly with no UserDefaults and no View involved.
struct IntroTour: Equatable {
    /// Where `RootView` persists "seen" (Raj's default: shown once for a
    /// fresh install right after setup, and once for an existing install at
    /// the next launch after this update).
    static let seenKey = "appIntroSeen"

    static let steps = IntroStep.allCases

    private(set) var index: Int?
    private(set) var seen: Bool
    private(set) var skipped = false
    private(set) var finished = false
    /// Set by `replay()`: `shouldShow` ignores `seen` once, until the tour
    /// ends again (which leaves `seen` exactly as it was: true).
    private(set) var replaying = false
    /// True unless some step in this run was advanced early (a tap, not a
    /// timeout). `skip()` always leaves it false. Read at `finished` for the
    /// `auto` field on `intro_finished`.
    private(set) var auto = true

    init(seen: Bool = false) {
        self.seen = seen
    }

    /// The step on screen, or nil before `start()` and after the tour ends.
    var step: IntroStep? { index.flatMap { Self.steps.indices.contains($0) ? Self.steps[$0] : nil } }

    /// Where the app should be: the current step's tab, or Home once the
    /// tour hasn't started or has ended.
    var tab: AppTab { step?.tab ?? .home }

    mutating func start() {
        index = 0
        skipped = false
        finished = false
        auto = true
    }

    /// A tap anywhere (or a real Next) advances at once, regardless of how
    /// much time is left on the step's clock. Counts as "not auto" for the
    /// `auto` flag Analytics reads at the end.
    mutating func next() {
        auto = false
        advance()
    }

    /// The step's own 2.5s clock ran out with no tap: same step transition
    /// as `next()`, but doesn't clear `auto` — this is what "every step
    /// timed out" means.
    mutating func advanceOnTimeout() {
        advance()
    }

    private mutating func advance() {
        guard let index else { return }
        let following = index + 1
        if Self.steps.indices.contains(following) {
            self.index = following
        } else {
            finish(skipped: false)
        }
    }

    /// Ends the tour at once, from any step, counted as skipped. Always
    /// counts as "not auto" — Raj asked, not a timer.
    mutating func skip() {
        auto = false
        finish(skipped: true)
    }

    /// Asked for from Help: runs the tour again even though `seen` is
    /// already true.
    mutating func replay() {
        replaying = true
        start()
    }

    private mutating func finish(skipped: Bool) {
        index = nil
        self.skipped = skipped
        finished = true
        seen = true
        replaying = false
    }

    /// Whether `RootView` should call `start()` right now: setup is done,
    /// nothing else is up, and either the tour has never been seen or a
    /// replay was asked for.
    func shouldShow(setupDone: Bool, setupShowing: Bool, locked: Bool) -> Bool {
        Self.shouldShow(setupDone: setupDone, seen: seen && !replaying, setupShowing: setupShowing, locked: locked)
    }

    /// The same rule as a pure function of its four inputs (the test plan's
    /// shape): setup done, not already seen, nothing else showing, not locked.
    static func shouldShow(setupDone: Bool, seen: Bool, setupShowing: Bool, locked: Bool) -> Bool {
        setupDone && !seen && !setupShowing && !locked
    }

    /// Whether the per-step timer should run at all. Never under Reduce
    /// Motion (a still ring stands in, Next/Skip are the only way to move)
    /// and never while VoiceOver is running (it would trap a VoiceOver user
    /// behind a clock they can't stop) — both gates live here, as one pure
    /// rule, so the View can't accidentally check only one of them.
    static func autoAdvances(reduceMotion: Bool, voiceOverRunning: Bool) -> Bool {
        !reduceMotion && !voiceOverRunning
    }
}

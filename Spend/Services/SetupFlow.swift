import Foundation

/// Which setup screens a person sees, and in what order, from their answers.
/// Pure (no SwiftUI, no stores), so every kind of person can be walked
/// through it in tests.
struct SetupFlow: Equatable {
    /// Questions first, then what the answers built, then the few chores.
    /// Nothing is asked for before the app has earned it.
    enum Step: Int, CaseIterable, Sendable {
        case welcome, account, goals, payment, currency, budget, checkIn, building, plan
        case cards, applePay
    }

    var goals: Set<SetupProfile.Goal> = []
    var payment: SetupProfile.Payment?
    var hasCards = false
    /// Sign in with Apple / Google is switched on in this build (needs the
    /// paid developer account's capability; see `Features.signIn`).
    var signInFeature = false

    func isShown(_ s: Step) -> Bool {
        switch s {
        case .account: signInFeature
        case .budget: goals.contains(.spendLess)
        case .applePay: payment != .cash
        default: true
        }
    }

    /// The next step this person will see, going forward or back. Going back
    /// never lands on the "building" pause (it would move on by itself).
    func neighbour(of s: Step, _ delta: Int) -> Step? {
        var i = s.rawValue + delta
        while let c = Step(rawValue: i) {
            if isShown(c), !(delta < 0 && c == .building) { return c }
            i += delta
        }
        return nil
    }

    /// Every step, start to end, going forward only.
    var path: [Step] {
        var out: [Step] = [.welcome]
        while let next = neighbour(of: out.last!, 1) { out.append(next) }
        return out
    }

    var questionSteps: [Step] {
        [.goals, .payment, .currency, .budget, .checkIn].filter(isShown)
    }

    /// "Question 2 of 5". Nil for steps that aren't questions.
    func counter(_ s: Step) -> String? {
        let steps = questionSteps
        guard let i = steps.firstIndex(of: s) else { return nil }
        return "Question \(i + 1) of \(steps.count)"
    }

    /// 0...1 for the progress bar, counting only steps this person sees.
    func progress(at step: Step) -> Double {
        let shown = Step.allCases.filter { $0 != .welcome && $0 != .building && isShown($0) }
        guard !shown.isEmpty else { return 0 }
        let reached = shown.lastIndex { $0.rawValue <= step.rawValue } ?? -1
        return Double(reached + 1) / Double(shown.count)
    }
}

// MARK: - Tap-through defaults (overhaul sub-spec 6)

extension SetupFlow {
    /// What setup saves for a question nobody answered. Every step can be
    /// passed with one tap on Continue; these are what that tap leaves behind.
    struct Defaults: Equatable {
        let currency: String
        let budget: Double
        /// Saved as the answer, but nothing is scheduled until the person
        /// says yes to notifications on Home (after the first auto-logged
        /// purchase), never during setup.
        let checkIn: SetupProfile.CheckIn
        let goals: Set<SetupProfile.Goal>
    }

    /// The phone's own currency when daily rates exist for it, no limit,
    /// a Sunday recap, no goals.
    static func defaults(locale: Locale) -> Defaults {
        Defaults(currency: Money.detectedHome(for: locale),
                 budget: 0, checkIn: .sunday, goals: [])
    }

    /// Nothing in setup is a required field: Continue always works, whatever
    /// has been answered so far. Kept as a function so the view has one
    /// place to ask, and a test can pin that the answer never changes.
    static func continueEnabled(at step: Step, answers: SetupFlow) -> Bool { true }

    /// The tap-through flow: "Continue" on every step, no permission alert
    /// during setup, "Do this later" on the plan goes straight to Home.
    /// The default since 25 Sep 2026. Debug builds show the old flow with
    /// SPEND_OLD_SETUP=1 (to compare, or to run the old-flow tests).
    static var usesNewFlow: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["SPEND_OLD_SETUP"] != "1"
        #else
        true
        #endif
    }
}

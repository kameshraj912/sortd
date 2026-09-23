import Foundation

/// Which setup screens a person sees, and in what order, from their answers.
/// Pure (no SwiftUI, no stores), so every kind of person can be walked
/// through it in tests.
struct SetupFlow: Equatable {
    /// Questions first, then what the answers built, then the few chores,
    /// then Pro. Nothing is asked for before the app has earned it.
    enum Step: Int, CaseIterable, Sendable {
        case welcome, goals, payment, currency, feeling, budget, checkIn, building, plan
        case cards, cardDetails, applePay, pro, email
    }

    var goals: Set<SetupProfile.Goal> = []
    var payment: SetupProfile.Payment?
    var hasCards = false
    /// The Gmail feature is switched on in this build.
    var gmailFeature = false
    var isPro = false

    var wantsGmail: Bool { payment == .online || goals.contains(.receipts) }

    func isShown(_ s: Step) -> Bool {
        switch s {
        case .budget: goals.contains(.spendLess)
        case .cardDetails: hasCards
        case .applePay: payment != .cash
        case .email: gmailFeature && isPro && wantsGmail
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
        [.goals, .payment, .currency, .feeling, .budget, .checkIn].filter(isShown)
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

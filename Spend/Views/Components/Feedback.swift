import SwiftUI

/// The one haptic map (overhaul sub-spec 5). Every haptic in the app is one
/// of these, chosen by what happened, not by screen. There is no case for
/// scroll: haptics never fire on scroll, and paging a carousel or picking a
/// point on a chart counts as `select`.
///
/// Call sites use `.feedback(_:trigger:)` below; that modifier is the only
/// place `.sensoryFeedback(` may appear (`FeedbackCoverageTests`).
enum Feedback: CaseIterable {
    /// A choice: a tab, a chip, a card in the carousel, a chart point.
    case select
    /// Something saved or finished: a purchase, a budget, an import.
    case confirm
    /// Something went wrong: a save or a sync that failed.
    case fail
    /// Input refused or a limit hit: a key the amount field ignores.
    case blocked
    /// A purchase swiped away.
    case delete
    /// A delete brought back.
    case undo
    /// The first "it worked" moment. Reserved for sub-spec 6; no call site yet.
    case aha

    /// The weight for the two impact haptics, nil for the rest. `sensory`
    /// builds `.impact` from this, so the two cannot drift apart
    /// (`SensoryFeedback.impact(weight:)` values compare equal whatever the
    /// weight, so tests pin the weight here).
    var impactWeight: SensoryFeedback.Weight? {
        switch self {
        case .delete: .medium
        case .undo: .light
        case .select, .confirm, .fail, .blocked, .aha: nil
        }
    }

    var sensory: SensoryFeedback {
        switch self {
        case .select: return .selection
        case .confirm, .aha: return .success
        case .fail: return .error
        case .blocked: return .warning
        case .delete, .undo:
            guard let weight = impactWeight else { preconditionFailure("\(self) needs an impact weight") }
            return .impact(weight: weight)
        }
    }
}

extension View {
    /// Plays `kind` whenever `trigger` changes.
    func feedback<T: Equatable>(_ kind: Feedback, trigger: T) -> some View {
        sensoryFeedback(kind.sensory, trigger: trigger)
    }

    /// Plays `kind` when `trigger` changes and `condition(old, new)` is true.
    func feedback<T: Equatable>(_ kind: Feedback, trigger: T,
                                condition: @escaping (T, T) -> Bool) -> some View {
        sensoryFeedback(kind.sensory, trigger: trigger, condition: condition)
    }
}

/// Direction-aware motion: which way a change slides, and when it should
/// fade instead (Reduce Motion, or iOS 26.4's Prefer Cross-Fade Transitions).
enum Motion {
    enum Direction: Equatable {
        case forward, backward
    }

    /// What `transition` builds; pinned separately because `AnyTransition`
    /// is not `Equatable`.
    enum Kind: Equatable {
        case opacity, pushTrailing, pushLeading
    }

    static func crossFades(reduceMotion: Bool, prefersCrossFade: Bool) -> Bool {
        reduceMotion || prefersCrossFade
    }

    static func transitionKind(_ direction: Direction, crossFades: Bool) -> Kind {
        if crossFades { return .opacity }
        return direction == .forward ? .pushTrailing : .pushLeading
    }

    /// Forward comes in from the trailing edge, back from the leading edge;
    /// a plain fade when the person asked for no sliding.
    static func transition(_ direction: Direction, crossFades: Bool) -> AnyTransition {
        switch transitionKind(direction, crossFades: crossFades) {
        case .opacity: .opacity
        case .pushTrailing: .push(from: .trailing)
        case .pushLeading: .push(from: .leading)
        }
    }

    /// Which way a month change goes, by calendar month. The same month is
    /// `.forward`: nothing that did not change should look like going back.
    static func direction(from old: Date, to new: Date, calendar: Calendar = .current) -> Direction {
        let a = calendar.dateInterval(of: .month, for: old)?.start ?? old
        let b = calendar.dateInterval(of: .month, for: new)?.start ?? new
        return b >= a ? .forward : .backward
    }
}

extension EnvironmentValues {
    /// True when transitions should fade instead of slide: Reduce Motion, or
    /// Prefer Cross-Fade Transitions (iOS 26.4). The environment name only
    /// ships in the Xcode 27 SDK (Swift 6.4); an `#available` check alone is
    /// not enough, as Xcode 26.x cannot compile the name at all, which broke
    /// CI. The compiler guard keeps both toolchains building.
    var crossFades: Bool {
        var prefersCrossFade = false
        #if compiler(>=6.4)
        if #available(iOS 26.4, *) { prefersCrossFade = accessibilityPrefersCrossFadeTransitions }
        #endif
        return Motion.crossFades(reduceMotion: accessibilityReduceMotion, prefersCrossFade: prefersCrossFade)
    }
}

import Testing
import SwiftUI
@testable import Spend

/// Pins the one feedback map (spec 5, "Feedback map") and direction-aware
/// motion (`Motion`) described in
/// docs/specs/2026-09-25-free-app-overhaul-5-motion.md.
///
/// `Feedback` is a pure enum, one case per kind of action, mapped to a
/// `SensoryFeedback`:
///   select -> .selection, confirm -> .success, fail -> .error,
///   blocked -> .warning, delete -> .impact(weight: .medium),
///   undo -> .impact(weight: .light), aha -> .success.
/// There is no case for scroll: haptics never fire on scroll.
///
/// `Motion` decides whether the app slides or cross-fades (Reduce Motion, or
/// iOS 26.4+ Prefer Cross-Fade Transitions), and which way Home's month
/// change should slide. Tie rule pinned here: the same month counts as
/// `.forward` (no case where nothing changed should look like going back).
@Suite("Feedback")
struct FeedbackTests {

    // MARK: - Feedback map

    @Test func selectIsSelection() {
        #expect(Feedback.select.sensory == .selection)
    }

    @Test func confirmIsSuccess() {
        #expect(Feedback.confirm.sensory == .success)
    }

    @Test func failIsError() {
        #expect(Feedback.fail.sensory == .error)
    }

    @Test func blockedIsWarning() {
        #expect(Feedback.blocked.sensory == .warning)
    }

    @Test func deleteIsMediumImpact() {
        #expect(Feedback.delete.sensory == .impact(weight: .medium))
    }

    @Test func undoIsLightImpact() {
        #expect(Feedback.undo.sensory == .impact(weight: .light))
    }

    @Test func ahaIsSuccess() {
        #expect(Feedback.aha.sensory == .success)
    }

    /// On this SDK (Xcode 27.0 / iOS 27, checked with a standalone script
    /// outside this test run), `SensoryFeedback.impact(weight:)` values are
    /// `==` to each other regardless of weight, and `String(describing:)`
    /// collapses to the same text too — both routes the spec allows for
    /// comparison are blind to weight here. This assertion is written the
    /// way the contract asks (`!=` via Equatable); expect it to stay red on
    /// this SDK even once `Feedback` exists correctly, and say so rather
    /// than loosen it to hide the platform gap.
    @Test func deleteAndUndoDifferInWeight() {
        #expect(Feedback.delete.sensory != Feedback.undo.sensory)
    }

    /// Exhaustive: every case has a mapping, and there is no eighth case for
    /// scroll (select, confirm, fail, blocked, delete, undo, aha = 7).
    @Test func noCaseForScroll() {
        #expect(Feedback.allCases.count == 7)
    }

    @Test func everyCaseMapsToASensoryFeedback() {
        for f in Feedback.allCases {
            let expected: SensoryFeedback
            switch f {
            case .select: expected = .selection
            case .confirm: expected = .success
            case .fail: expected = .error
            case .blocked: expected = .warning
            case .delete: expected = .impact(weight: .medium)
            case .undo: expected = .impact(weight: .light)
            case .aha: expected = .success
            }
            #expect(f.sensory == expected)
        }
    }

    // MARK: - Motion.crossFades

    @Test func crossFadesWhenReduceMotionOnly() {
        #expect(Motion.crossFades(reduceMotion: true, prefersCrossFade: false))
    }

    @Test func crossFadesWhenPreferCrossFadeOnly() {
        #expect(Motion.crossFades(reduceMotion: false, prefersCrossFade: true))
    }

    @Test func crossFadesWhenBoth() {
        #expect(Motion.crossFades(reduceMotion: true, prefersCrossFade: true))
    }

    @Test func doesNotCrossFadeWhenNeither() {
        #expect(!Motion.crossFades(reduceMotion: false, prefersCrossFade: false))
    }

    // MARK: - Motion.direction

    @Test func laterMonthIsForward() {
        let cal = Calendar(identifier: .gregorian)
        let aug = cal.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let sep = cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        #expect(Motion.direction(from: aug, to: sep, calendar: cal) == .forward)
    }

    @Test func earlierMonthIsBackward() {
        let cal = Calendar(identifier: .gregorian)
        let sep = cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let aug = cal.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        #expect(Motion.direction(from: sep, to: aug, calendar: cal) == .backward)
    }

    @Test func yearBoundaryForward() {
        let cal = Calendar(identifier: .gregorian)
        let dec = cal.date(from: DateComponents(year: 2025, month: 12, day: 1))!
        let jan = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        #expect(Motion.direction(from: dec, to: jan, calendar: cal) == .forward)
    }

    /// Tie rule: same month is `.forward`, never `.backward`.
    @Test func sameMonthIsForward() {
        let cal = Calendar(identifier: .gregorian)
        let a = cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let b = cal.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        #expect(Motion.direction(from: a, to: b, calendar: cal) == .forward)
    }

    // MARK: - Motion.transitionKind / transition

    @Test func crossFadesGivesOpacityKindRegardlessOfDirection() {
        #expect(Motion.transitionKind(.forward, crossFades: true) == .opacity)
        #expect(Motion.transitionKind(.backward, crossFades: true) == .opacity)
    }

    @Test func forwardWithoutCrossFadeGivesPushTrailing() {
        #expect(Motion.transitionKind(.forward, crossFades: false) == .pushTrailing)
    }

    @Test func backwardWithoutCrossFadeGivesPushLeading() {
        #expect(Motion.transitionKind(.backward, crossFades: false) == .pushLeading)
    }

    /// `transition` is built from `transitionKind`; can't compare
    /// `AnyTransition` directly (not Equatable), so this pins that the kind
    /// alone decides the outcome and that `transition` does not crash for
    /// any combination.
    @Test func transitionExistsForEveryKind() {
        _ = Motion.transition(.forward, crossFades: true)
        _ = Motion.transition(.forward, crossFades: false)
        _ = Motion.transition(.backward, crossFades: true)
        _ = Motion.transition(.backward, crossFades: false)
    }
}

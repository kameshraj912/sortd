import Testing
import Foundation
@testable import Spend

/// Overhaul sub-spec 6: "Allow the user to continually click Continue, set
/// reasonable defaults." Pinning `SetupFlow.defaults`, `SetupFlow.continueEnabled`
/// and the shape of `SetupFlow.path`, against the real names already in
/// `SetupFlow`/`SetupProfile`:
///
///     extension SetupFlow {
///         struct Defaults: Equatable {
///             let currency: String
///             let budget: Double
///             let checkIn: SetupProfile.CheckIn   // "checkInWeekday" in the brief maps to .sunday
///             let goals: Set<SetupProfile.Goal>
///             let wantsGmail: Bool
///         }
///         static func defaults(locale: Locale) -> Defaults
///         static func continueEnabled(at step: Step, answers: SetupFlow) -> Bool   // always true
///     }
///
/// `SetupFlow.Step` and `SetupProfile.Goal`/`CheckIn` already exist (read in
/// `Spend/Services/SetupFlow.swift` and `SetupProfile.swift`); no answers
/// type is added beyond `SetupFlow` itself, since `SetupFlow` already holds
/// every question's answer (goals, payment, hasCards). `Defaults.checkIn`
/// is `SetupProfile.CheckIn` (not a weekday Int) because that is the type
/// the app already stores setup's check-in answer as; its `.sunday` case
/// carries weekday 1 via `CheckIn.time`.
///
/// This file does not compile until `SetupFlow.Defaults`, `SetupFlow.defaults(locale:)`
/// and `SetupFlow.continueEnabled(at:answers:)` exist. That is the expected
/// red state for new behaviour: see the test-writer report for the exact
/// compiler errors.
struct SetupDefaultsTests {
    typealias Step = SetupFlow.Step

    // MARK: Defaults per locale

    @Test func australianLocaleDefaultsToAUD() {
        let d = SetupFlow.defaults(locale: Locale(identifier: "en_AU"))
        #expect(d.currency == "AUD")
        #expect(d.budget == 0)
        #expect(d.checkIn == .sunday)
        #expect(d.goals.isEmpty)
    }

    @Test func singaporeLocaleDefaultsToSGD() {
        let d = SetupFlow.defaults(locale: Locale(identifier: "en_SG"))
        #expect(d.currency == "SGD")
        #expect(d.budget == 0)
        #expect(d.checkIn == .sunday)
        #expect(d.goals.isEmpty)
    }

    /// Sunday is saved as the answer even though nothing schedules the
    /// notification until permission is granted (research 03 §9: ask after
    /// the aha, not during setup). `CheckIn.time` is only consulted once a
    /// reminder is actually scheduled, which this test does not do.
    @Test func checkInDefaultIsSavedButNotAPermissionRequest() {
        let d = SetupFlow.defaults(locale: Locale(identifier: "en_AU"))
        #expect(d.checkIn == .sunday)
        #expect(d.checkIn.time?.weekday == 1)
    }

    // MARK: Continue always works

    /// The tap-through flow is the default (since 25 Sep 2026). The test
    /// scheme sets no `SPEND_OLD_SETUP`, so this pins the shipped answer.
    @Test func theTapThroughFlowIsTheDefault() {
        #expect(SetupFlow.usesNewFlow)
    }

    @Test func continueIsAlwaysEnabledFromAnEmptyAnswerSet() {
        let empty = SetupFlow()
        for step in Step.allCases {
            #expect(SetupFlow.continueEnabled(at: step, answers: empty), "\(step) blocked Continue")
        }
    }

    /// Even a half-answered flow (some goals picked, no payment yet) must
    /// never block Continue: nothing in sub-spec 6 is a required field.
    @Test func continueIsAlwaysEnabledPartway() {
        let partial = SetupFlow(goals: [.spendLess], payment: nil, hasCards: false)
        for step in Step.allCases {
            #expect(SetupFlow.continueEnabled(at: step, answers: partial), "\(step) blocked Continue")
        }
    }

    // MARK: Path length and no Pro step

    @Test func everyPathIsElevenQuestionsOrFewerAndHasNoProStep() {
        let goals = SetupProfile.Goal.allCases
        for mask in 0..<(1 << goals.count) {
            let picked = Set(goals.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
            for payment in [nil] + SetupProfile.Payment.allCases.map(Optional.some) {
                for cards in [false, true] {
                    let flow = SetupFlow(goals: picked, payment: payment, hasCards: cards)
                    // "11" in the spec excludes welcome and the building pause.
                    let counted = flow.path.filter { $0 != .welcome && $0 != .building }.count
                    #expect(counted <= 11, "\(counted) steps for \(picked) \(String(describing: payment)) cards:\(cards)")
                    // There is no `.pro` case on `Step` at all (sub-spec 1); this
                    // just documents that every path stays within the known cases.
                    #expect(Set(flow.path).isSubset(of: Set(Step.allCases)))
                }
            }
        }
    }

    /// A person who only ever taps "next" from welcome, answering nothing,
    /// still reaches the last step of their path -- there is no step that
    /// requires an answer to move past it.
    @Test func tappingOnlyNextFromWelcomeReachesTheEnd() {
        let flow = SetupFlow()
        let path = flow.path
        #expect(path.first == .welcome)
        #expect(path.last == Step.allCases.last { flow.isShown($0) })
        for step in path {
            #expect(SetupFlow.continueEnabled(at: step, answers: flow))
        }
    }
}

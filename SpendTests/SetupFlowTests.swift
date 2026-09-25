import Testing
import Foundation
@testable import Spend

/// Different kinds of people walked through setup. Each checks the screens
/// they see, in order, and what their plan lists.
///
/// Free-app contract (overhaul sub-spec 1, `docs/specs/2026-09-25-free-app-overhaul-1-free.md`):
/// there is no Pro step, ever, and no `isPro` flag on `SetupFlow`.
///
///     struct SetupFlow: Equatable {
///         enum Step: Int, CaseIterable, Sendable {
///             case welcome, goals, payment, currency, feeling, budget, checkIn, building, plan
///             case cards, cardDetails, applePay, email
///         }
///         var goals: Set<SetupProfile.Goal> = []
///         var payment: SetupProfile.Payment?
///         var hasCards = false
///         var gmailFeature = false
///         // no `isPro`
///         var wantsGmail: Bool { payment == .online || goals.contains(.receipts) }
///         func isShown(_ s: Step) -> Bool {
///             switch s {
///             case .budget: goals.contains(.spendLess)
///             case .cardDetails: hasCards
///             case .applePay: payment != .cash
///             case .email: gmailFeature && wantsGmail   // no isPro
///             default: true
///             }
///         }
///     }
///
/// These tests are written against that signature. Until swift-builder drops
/// `isPro`/`.pro` from `SetupFlow`, this whole file fails to compile
/// (`SetupFlow` has no `isPro`/`hasTipped`... has extra `isPro` member and
/// `Step` still has `.pro`; the initializer calls below don't match). That is
/// expected: see the test-writer report for the exact compiler errors.
struct SetupFlowTests {
    typealias Step = SetupFlow.Step

    private func tasks(_ flow: SetupFlow) -> [SetupTask] {
        SetupChecklist.tasks(flow: flow, hasCards: flow.hasCards, tapped: false, widgetAdded: false, gmailConnected: false)
    }

    // MARK: The checklist on the plan and on Home

    @Test func checklistStartsOneStepInAndTicksFromRealData() {
        let flow = SetupFlow(goals: [], payment: .applePay)
        let fresh = tasks(flow)
        #expect(SetupChecklist.doneCount(fresh) == 1)      // answering the questions
        #expect(!SetupChecklist.isComplete(fresh))
        let set = SetupChecklist.tasks(flow: flow, hasCards: true, tapped: true, widgetAdded: false, gmailConnected: false)
        #expect(SetupChecklist.isComplete(set))
        // A cash user is done once the widget is on the Home Screen, not by tapping.
        let cash = SetupFlow(payment: .cash)
        #expect(!SetupChecklist.isComplete(SetupChecklist.tasks(flow: cash, hasCards: true, tapped: true, widgetAdded: false, gmailConnected: false)))
        #expect(SetupChecklist.isComplete(SetupChecklist.tasks(flow: cash, hasCards: true, tapped: false, widgetAdded: true, gmailConnected: false)))
    }

    // MARK: People

    @Test func cashUserWhoWantsToSpendLess() {
        let flow = SetupFlow(goals: [.spendLess], payment: .cash)
        // No Pro step, no Apple Pay chores for someone who mostly pays cash.
        #expect(flow.path == [.welcome, .goals, .payment, .currency, .feeling, .budget, .checkIn,
                              .building, .plan, .cards])
        #expect(tasks(flow).map(\.id) == ["answers", "cards", "widget"])
        #expect(flow.counter(.budget) == "Question 5 of 6")
    }

    @Test func notSureYetApplePayUser() {
        let flow = SetupFlow(goals: [], payment: nil)
        #expect(flow.path == [.welcome, .goals, .payment, .currency, .feeling, .checkIn,
                              .building, .plan, .cards, .applePay])
        #expect(!flow.path.contains(.budget))
        #expect(tasks(flow).map(\.id) == ["answers", "cards", "applePay"])
        #expect(flow.counter(.checkIn) == "Question 5 of 5")
    }

    /// A person whose goals want receipts, with Gmail switched on in this
    /// build, sees the email step -- with no Pro condition anywhere.
    @Test func receiptsGoalWithGmailFeatureShowsTheEmailStep() {
        let flow = SetupFlow(goals: [.receipts], payment: .online, hasCards: true, gmailFeature: true)
        #expect(flow.path == [.welcome, .goals, .payment, .currency, .feeling, .checkIn, .building, .plan,
                              .cards, .cardDetails, .applePay, .email])
        #expect(tasks(flow).map(\.id) == ["answers", "cards", "applePay", "gmail"])
    }

    /// Gmail switched off in this build: never the email step, never the
    /// gmail chore, no matter what the goals say.
    @Test func gmailFeatureOffNeverShowsTheEmailStep() {
        let flow = SetupFlow(goals: [.receipts], payment: .online, gmailFeature: false)
        #expect(!flow.path.contains(.email))
        #expect(!tasks(flow).contains { $0.id == "gmail" })
    }

    @Test func goingBackSkipsTheBuildingPause() {
        let flow = SetupFlow(goals: [.spendLess], payment: .applePay)
        #expect(flow.neighbour(of: .plan, -1) == .checkIn)
        #expect(flow.neighbour(of: .checkIn, 1) == .building)
        #expect(flow.neighbour(of: .goals, -1) == .welcome)
        #expect(flow.neighbour(of: .welcome, -1) == nil)
    }

    /// A cash payer with none of the optional steps ends at `.cards`: there
    /// is no `.pro` step to land on any more.
    @Test func lastStepHasNoNext() {
        let flow = SetupFlow(payment: .cash)
        #expect(flow.path.last == .cards)
        #expect(flow.neighbour(of: .cards, 1) == nil)
    }

    @Test func questionsOnlyHaveCounters() {
        let flow = SetupFlow(goals: [.spendLess])
        #expect(flow.counter(.goals) == "Question 1 of 6")
        #expect(flow.counter(.plan) == nil)
        #expect(flow.counter(.cards) == nil)
    }

    // MARK: Every combination

    static let everyone: [SetupFlow] = {
        let goals = SetupProfile.Goal.allCases
        var people: [SetupFlow] = []
        for mask in 0..<(1 << goals.count) {
            let picked = Set(goals.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
            for payment in [nil] + SetupProfile.Payment.allCases.map(Optional.some) {
                for cards in [false, true] {
                    for gmail in [false, true] {
                        people.append(SetupFlow(goals: picked, payment: payment, hasCards: cards,
                                                gmailFeature: gmail))
                    }
                }
            }
        }
        return people
    }()

    @Test func everyCombinationHasASaneRoute() {
        #expect(Self.everyone.count == 32 * 6 * 4)
        for flow in Self.everyone {
            let path = flow.path
            #expect(path.first == .welcome)
            #expect(path.contains(.building) && path.contains(.plan))
            // In order, no repeats.
            #expect(path.map(\.rawValue) == path.map(\.rawValue).sorted())
            #expect(Set(path).count == path.count)
            // Conditional steps only when they should be.
            #expect(path.contains(.budget) == flow.goals.contains(.spendLess))
            #expect(path.contains(.applePay) == (flow.payment != .cash))
            #expect(path.contains(.cardDetails) == flow.hasCards)
            #expect(path.contains(.email) == (flow.gmailFeature && flow.wantsGmail))
            // The path ends on the last step (in declaration order) this
            // person is shown -- no fixed "last screen" any more.
            let lastShown = Step.allCases.last { flow.isShown($0) }
            #expect(path.last == lastShown)
            // Going back from any step lands on the step before it, skipping the pause.
            for (i, step) in path.enumerated().dropFirst() {
                let before = path[i - 1] == .building ? path[i - 2] : path[i - 1]
                #expect(flow.neighbour(of: step, -1) == before)
            }
            // The bar only moves forward and ends full.
            let bar = path.map { flow.progress(at: $0) }
            #expect(bar == bar.sorted())
            #expect(bar.last == 1)
            // Every question has a counter that ends at "n of n".
            let questions = flow.questionSteps
            #expect(flow.counter(questions.last!) == "Question \(questions.count) of \(questions.count)")
        }
    }
}

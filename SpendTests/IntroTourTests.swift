import Testing
import Foundation
@testable import Spend

/// `IntroTour` is pure: no Views, no UserDefaults, no TipKit. Contract lives
/// in docs/specs/2026-09-25-app-intro.md.
struct IntroTourTests {

    // MARK: Steps

    @Test func stepsAreAddInsightsMoveInOrder() {
        #expect(IntroTour.steps == [.add, .insights, .move])
    }

    @Test func startMovesToStepZero() {
        var tour = IntroTour()
        tour.start()
        #expect(tour.step == .add)
    }

    @Test func nextTwiceReachesMove() {
        var tour = IntroTour()
        tour.start()
        tour.next()
        tour.next()
        #expect(tour.step == .move)
    }

    @Test func nextOnTheLastStepFinishesUnskipped() {
        var tour = IntroTour()
        tour.start()
        tour.next()
        tour.next()
        tour.next()
        #expect(tour.step == nil)
        #expect(tour.finished == true)
        #expect(tour.seen == true)
        #expect(tour.skipped == false)
    }

    @Test func skipAtAnyStepFinishesSkipped() {
        var tour = IntroTour()
        tour.start()
        tour.next()
        tour.skip()
        #expect(tour.step == nil)
        #expect(tour.finished == true)
        #expect(tour.seen == true)
        #expect(tour.skipped == true)
    }

    // MARK: shouldShow (pure)

    @Test func shouldShowWhenSetupDoneNotSeenNothingElseUp() {
        #expect(IntroTour.shouldShow(setupDone: true, seen: false, setupShowing: false, locked: false) == true)
    }

    @Test func shouldShowFalseWhenAlreadySeen() {
        #expect(IntroTour.shouldShow(setupDone: true, seen: true, setupShowing: false, locked: false) == false)
    }

    @Test func shouldShowFalseWhileSetupShowing() {
        #expect(IntroTour.shouldShow(setupDone: true, seen: false, setupShowing: true, locked: false) == false)
    }

    @Test func shouldShowFalseWhileLocked() {
        #expect(IntroTour.shouldShow(setupDone: true, seen: false, setupShowing: false, locked: true) == false)
    }

    @Test func shouldShowFalseWhenSetupNotDone() {
        #expect(IntroTour.shouldShow(setupDone: false, seen: false, setupShowing: false, locked: false) == false)
    }

    // MARK: Replay

    @Test func replayShowsAgainEvenWhenSeen() {
        var tour = IntroTour(seen: true)
        tour.replay()
        #expect(tour.shouldShow(setupDone: true, setupShowing: false, locked: false) == true)
        #expect(tour.step == .add)
    }

    @Test func replaySeenStaysTrueAfterItFinishes() {
        var tour = IntroTour(seen: true)
        tour.replay()
        tour.next()
        tour.next()
        tour.next()
        #expect(tour.seen == true)
        #expect(tour.shouldShow(setupDone: true, setupShowing: false, locked: false) == false)
    }

    // MARK: Tab per step

    @Test func tabFollowsEachStep() {
        var tour = IntroTour()
        tour.start()
        #expect(tour.tab == .home)
        tour.next()
        #expect(tour.tab == .insights)
        tour.next()
        #expect(tour.tab == .activity)
    }

    @Test func tabIsHomeAfterFinishing() {
        var tour = IntroTour()
        tour.start()
        tour.skip()
        #expect(tour.tab == .home)
    }

    // MARK: Timing and motion

    @Test func stepMotionDurationsSumUnderNineSeconds() {
        let total = IntroStep.allCases.reduce(0) { $0 + $1.motionDuration }
        #expect(total <= 9)
    }

    @Test func everyStepHasNoMotionUnderReduceMotion() {
        for step in IntroStep.allCases {
            #expect(step.motion(reduceMotion: true) == .none)
        }
    }

    @Test func stepsHaveMotionWhenMotionIsAllowed() {
        for step in IntroStep.allCases {
            #expect(step.motion(reduceMotion: false) != .none)
        }
    }

    // MARK: Copy

    @Test func linesAreShortAndPlain() {
        for step in IntroStep.allCases {
            #expect(step.line.count <= 60, "\(step): \(step.line.count) chars")
            #expect(!step.line.localizedCaseInsensitiveContains("pro"), "\(step)")
        }
    }

    @Test func voiceOverLabelsNameTheirControl() {
        #expect(IntroStep.add.accessibilityLabel.localizedCaseInsensitiveContains("plus"))
        #expect(IntroStep.insights.accessibilityLabel.localizedCaseInsensitiveContains("insights"))
        #expect(IntroStep.move.accessibilityLabel.localizedCaseInsensitiveContains("tab bar"))
    }

    @Test func voiceOverLabelsCarryTheStepPosition() {
        #expect(IntroStep.add.accessibilityLabel.hasPrefix("Step 1 of 3."))
        #expect(IntroStep.insights.accessibilityLabel.hasPrefix("Step 2 of 3."))
        #expect(IntroStep.move.accessibilityLabel.hasPrefix("Step 3 of 3."))
    }
}

import Testing
import Foundation
@testable import Spend

/// `IntroTour` is pure: no Views, no UserDefaults, no TipKit. Contract lives
/// in docs/specs/2026-09-26-app-intro-v2.md.
struct IntroTourTests {

    // MARK: Steps

    @Test func stepsAreAddInsightsSwipeInOrder() {
        #expect(IntroTour.steps == [.add, .insights, .swipe])
    }

    @Test func startMovesToStepZero() {
        var tour = IntroTour()
        tour.start()
        #expect(tour.step == .add)
    }

    @Test func nextTwiceReachesSwipe() {
        var tour = IntroTour()
        tour.start()
        tour.next()
        tour.next()
        #expect(tour.step == .swipe)
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
        #expect(IntroStep.swipe.accessibilityLabel.localizedCaseInsensitiveContains("purchase"))
        #expect(IntroStep.swipe.accessibilityLabel.localizedCaseInsensitiveContains("Activity"))
    }

    @Test func voiceOverLabelsCarryTheStepPosition() {
        #expect(IntroStep.add.accessibilityLabel.hasPrefix("Step 1 of 3."))
        #expect(IntroStep.insights.accessibilityLabel.hasPrefix("Step 2 of 3."))
        #expect(IntroStep.swipe.accessibilityLabel.hasPrefix("Step 3 of 3."))
    }

    /// Activity is one list again (spec 2026-10-03): there are no day
    /// arrows to point at, so step 3 teaches the row swipe instead.
    @Test func swipeStepTeachesTheRowSwipeNotArrows() {
        #expect(IntroStep.swipe.line == "Swipe a purchase to change or delete it")
        #expect(!IntroStep.swipe.line.localizedCaseInsensitiveContains("arrow"))
        #expect(!IntroStep.swipe.voiceOverTarget.localizedCaseInsensitiveContains("arrow"))
        #expect(IntroStep.swipe.tab == .activity)
    }

    @Test func swipeStepSlidesAFingerUnlessReduceMotion() {
        #expect(IntroStep.swipe.motion(reduceMotion: false) == .swipeLeft)
        #expect(IntroStep.swipe.motion(reduceMotion: true) == .none)
    }

    // MARK: Auto flag

    @Test func autoStaysTrueWhenEveryStepTimesOut() {
        var tour = IntroTour()
        tour.start()
        tour.advanceOnTimeout()
        tour.advanceOnTimeout()
        tour.advanceOnTimeout()
        #expect(tour.finished == true)
        #expect(tour.auto == true)
    }

    @Test func autoGoesFalseAfterOneEarlyTap() {
        var tour = IntroTour()
        tour.start()
        tour.advanceOnTimeout()
        tour.next() // an early tap on step 2
        tour.advanceOnTimeout()
        #expect(tour.finished == true)
        #expect(tour.auto == false)
    }

    @Test func skipAlwaysLeavesAutoFalse() {
        var tour = IntroTour()
        tour.start()
        tour.skip()
        #expect(tour.auto == false)
    }

    @Test func autoResetsOnEachStart() {
        var tour = IntroTour()
        tour.start()
        tour.next()
        tour.skip()
        #expect(tour.auto == false)
        tour.start()
        #expect(tour.auto == true)
    }

    // MARK: Reduce Motion / VoiceOver gate for the timer

    @Test func autoAdvanceNeverRunsUnderReduceMotionOrVoiceOver() {
        #expect(IntroTour.autoAdvances(reduceMotion: true, voiceOverRunning: false) == false)
        #expect(IntroTour.autoAdvances(reduceMotion: false, voiceOverRunning: true) == false)
        #expect(IntroTour.autoAdvances(reduceMotion: true, voiceOverRunning: true) == false)
        #expect(IntroTour.autoAdvances(reduceMotion: false, voiceOverRunning: false) == true)
    }
}

/// `IntroCountdown`: pure `Date` math, no sleeping — every test drives it
/// with injected dates, never a real clock.
struct IntroCountdownTests {
    private let epoch = Date(timeIntervalSinceReferenceDate: 0)

    @Test func countsDownFromStepStart() {
        let countdown = IntroCountdown(startedAt: epoch)
        #expect(countdown.remaining(at: epoch, duration: 2.5) == 2.5)
        #expect(countdown.remaining(at: epoch.addingTimeInterval(1), duration: 2.5) == 1.5)
    }

    @Test func remainingNeverGoesNegative() {
        let countdown = IntroCountdown(startedAt: epoch)
        #expect(countdown.remaining(at: epoch.addingTimeInterval(10), duration: 2.5) == 0)
    }

    @Test func pauseStopsTheClockAtTheMomentItPaused() {
        var countdown = IntroCountdown(startedAt: epoch)
        countdown.pause(at: epoch.addingTimeInterval(1)) // 1.5s left of 2.5s
        // Time keeps passing in the real world; the paused countdown must not move.
        #expect(countdown.remaining(at: epoch.addingTimeInterval(1), duration: 2.5) == 1.5)
        #expect(countdown.remaining(at: epoch.addingTimeInterval(5), duration: 2.5) == 1.5)
    }

    @Test func resumeContinuesFromWhereItPausedNotFromZero() {
        var countdown = IntroCountdown(startedAt: epoch)
        countdown.pause(at: epoch.addingTimeInterval(1)) // paused with 1.5s left
        countdown.resume(at: epoch.addingTimeInterval(4)) // held for 3s; doesn't count
        // 1s of real elapsed before the pause, plus 0s since resume (same instant).
        #expect(countdown.remaining(at: epoch.addingTimeInterval(4), duration: 2.5) == 1.5)
        // 0.5s further after resuming should draw down normally.
        #expect(countdown.remaining(at: epoch.addingTimeInterval(4.5), duration: 2.5) == 1.0)
    }

    @Test func isPausedReflectsState() {
        var countdown = IntroCountdown(startedAt: epoch)
        #expect(countdown.isPaused == false)
        countdown.pause(at: epoch.addingTimeInterval(1))
        #expect(countdown.isPaused == true)
        countdown.resume(at: epoch.addingTimeInterval(2))
        #expect(countdown.isPaused == false)
    }

    @Test func secondPauseWhileAlreadyPausedIsIgnored() {
        var countdown = IntroCountdown(startedAt: epoch)
        countdown.pause(at: epoch.addingTimeInterval(1))
        countdown.pause(at: epoch.addingTimeInterval(3)) // ignored: already paused
        countdown.resume(at: epoch.addingTimeInterval(4))
        // Paused window counted is 1s→4s (3s), not 3s→4s (1s).
        #expect(countdown.remaining(at: epoch.addingTimeInterval(4), duration: 2.5) == 1.5)
    }

    /// The contract behind the view's `.task(id: step)` restart: whatever
    /// happened on the step just left (a tap 1s in, in this case) must not
    /// carry forward — the next step's countdown is a brand new instance,
    /// started at the moment of the tap, with the full duration ahead of it
    /// and the segment's fill back at zero. (A real bug had a step's own
    /// task keep polling after being cancelled by the tap and calling
    /// `onTimeout()` again on the *next* step using the *old* step's
    /// deadline — cutting the new step short. That race lives in the view,
    /// not here, but this pins down what "fresh" has to mean for it.)
    @Test func newCountdownAfterATapStartsFullRegardlessOfPriorElapsedTime() {
        let stepOneStart = epoch
        let tapAt = stepOneStart.addingTimeInterval(1.0) // tapped 1s into step 1
        let stepTwo = IntroCountdown(startedAt: tapAt)
        let remaining = stepTwo.remaining(at: tapAt, duration: IntroStep.stepDuration)
        #expect(remaining == IntroStep.stepDuration)
        let progress = 1 - remaining / IntroStep.stepDuration
        #expect(progress == 0)
    }
}

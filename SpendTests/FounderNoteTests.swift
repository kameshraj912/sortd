import Testing
import Foundation
@testable import Spend

/// The founder's note aha rule: `FounderNote.shouldShowAtAha` is pure
/// (no SwiftUI, no UserDefaults) so it can be tested directly. Each of the
/// four conditions has to hold at once, and any one of them false is enough
/// to say no.
struct FounderNoteTests {
    @Test func trueWhenEveryConditionHolds() {
        #expect(FounderNote.shouldShowAtAha(hasFirstAutoPurchase: true, seenBefore: false, setupDone: true,
                                             anotherSheetOrAlertShowing: false))
    }

    @Test func falseWithNoFirstAutoPurchaseYet() {
        #expect(!FounderNote.shouldShowAtAha(hasFirstAutoPurchase: false, seenBefore: false, setupDone: true,
                                              anotherSheetOrAlertShowing: false))
    }

    @Test func falseOnceAlreadySeen() {
        #expect(!FounderNote.shouldShowAtAha(hasFirstAutoPurchase: true, seenBefore: true, setupDone: true,
                                              anotherSheetOrAlertShowing: false))
    }

    @Test func falseDuringSetup() {
        #expect(!FounderNote.shouldShowAtAha(hasFirstAutoPurchase: true, seenBefore: false, setupDone: false,
                                              anotherSheetOrAlertShowing: false))
    }

    @Test func falseOverAnotherSheetOrAlert() {
        #expect(!FounderNote.shouldShowAtAha(hasFirstAutoPurchase: true, seenBefore: false, setupDone: true,
                                              anotherSheetOrAlertShowing: true))
    }

    // MARK: hasBeenSeen / markSeen — once only, ever

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "FounderNoteTests-\(UUID().uuidString)")!
    }

    @Test func notSeenByDefault() {
        let d = defaults()
        #expect(!FounderNote.hasBeenSeen(defaults: d))
    }

    @Test func markSeenStaysSeen() {
        let d = defaults()
        FounderNote.markSeen(defaults: d)
        #expect(FounderNote.hasBeenSeen(defaults: d))
    }

    @Test func markSeenIsIdempotentOnTheStoredMoment() {
        let d = defaults()
        let first = Date(timeIntervalSince1970: 1_790_000_000)
        let later = Date(timeIntervalSince1970: 1_790_100_000)
        FounderNote.markSeen(defaults: d, now: first)
        FounderNote.markSeen(defaults: d, now: later)
        #expect(d.double(forKey: FounderNote.seenAtKey) == first.timeIntervalSince1970)
    }
}

import Testing
import Foundation
@testable import Spend

/// Pro given away by code. The point of these is that the door only opens
/// for the right knock, and that Delete All Data really deletes it.
struct CompedProTests {

    private func scratch() -> UserDefaults {
        let name = "comped-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func aRealCodeUnlocksPro() {
        let d = scratch()
        #expect(!CompedPro.isActive(d))
        #expect(CompedPro.redeem("iamtheonewhobudgets", d) == .unlocked("the one who budgets"))
        #expect(CompedPro.isActive(d))
    }

    @Test func codesIgnoreCaseSpacesAndDashes() {
        for written in ["Greed Is Good", "GREED-IS-GOOD", "  greed   is  good  ", "greed_is_good"] {
            let d = scratch()
            #expect(CompedPro.redeem(written, d).isSuccess, "\(written) should work")
            #expect(CompedPro.isActive(d))
        }
    }

    @Test func everyCodeWorks() {
        for code in ["iamtheonewhobudgets", "thereisnobudget", "wedontalkaboutbrunch",
                     "ihavenomoneyandimustscream", "greedisgood", "whatsinthebox",
                     "latestagecapitalism", "sortdbyraj"] {
            let d = scratch()
            #expect(CompedPro.redeem(code, d).isSuccess, "\(code) should work")
        }
    }

    @Test func aWrongCodeChangesNothing() {
        let d = scratch()
        #expect(CompedPro.redeem("letmein", d) == .notACode)
        #expect(CompedPro.redeem("", d) == .notACode)
        #expect(CompedPro.redeem("   ", d) == .notACode)
        #expect(!CompedPro.isActive(d))
    }

    @Test func redeemingTwiceSaysSoRatherThanPretendingItIsNew() {
        let d = scratch()
        #expect(CompedPro.redeem("greedisgood", d).isSuccess)
        #expect(CompedPro.redeem("greedisgood", d) == .alreadyUnlocked)
        #expect(CompedPro.isActive(d))
    }

    @Test func deletingEverythingTakesProBack() {
        let d = scratch()
        CompedPro.redeem("greedisgood", d)
        #expect(CompedPro.isActive(d))
        CompedPro.clear(d)
        #expect(!CompedPro.isActive(d))
    }

    @Test func theCodesAreNotStoredInPlainText() {
        // The lookup is by hash, so a real code and its hash differ.
        #expect(CompedPro.hash("greedisgood") != "greedisgood")
        #expect(CompedPro.hash("greedisgood").count == 64)
        // And the same input always gives the same hash, or nothing works.
        #expect(CompedPro.hash("Greed Is Good") == CompedPro.hash("greedisgood"))
    }

    @Test func knockingFiveTimesOpensTheDoor() async {
        await MainActor.run {
            let knock = SecretKnock.shared
            knock.reset()
            knock.isOpen = false
            for _ in 0..<4 {
                knock.knock()
                #expect(!knock.isOpen)
            }
            #expect(knock.hint == "One more.")
            knock.knock()
            #expect(knock.isOpen)
            knock.isOpen = false
            knock.reset()
        }
    }
}

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
        #expect(CompedPro.redeem("maximumeffort", d) == .unlocked("maximum effort"))
        #expect(CompedPro.isActive(d))
    }

    @Test func codesIgnoreCaseSpacesAndDashes() {
        for written in ["Maximum Effort", "MAXIMUM-EFFORT", "  maximum   effort  ", "maximum_effort"] {
            let d = scratch()
            #expect(CompedPro.redeem(written, d).isSuccess, "\(written) should work")
            #expect(CompedPro.isActive(d))
        }
    }

    @Test func everyCodeWorks() {
        for code in ["maximumeffort", "chimichangas", "sortdsortd"] {
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
        #expect(CompedPro.redeem("chimichangas", d).isSuccess)
        #expect(CompedPro.redeem("chimichangas", d) == .alreadyUnlocked)
        #expect(CompedPro.isActive(d))
    }

    @Test func deletingEverythingTakesProBack() {
        let d = scratch()
        CompedPro.redeem("maximumeffort", d)
        #expect(CompedPro.isActive(d))
        CompedPro.clear(d)
        #expect(!CompedPro.isActive(d))
    }

    @Test func theCodesAreNotStoredInPlainText() {
        // The lookup is by hash, so a real code and its hash differ.
        #expect(CompedPro.hash("maximumeffort") != "maximumeffort")
        #expect(CompedPro.hash("maximumeffort").count == 64)
        // And the same input always gives the same hash, or nothing works.
        #expect(CompedPro.hash("Maximum Effort") == CompedPro.hash("maximumeffort"))
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

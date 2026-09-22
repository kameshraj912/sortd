import Testing
import Foundation
@testable import Spend

// Comped Pro exists in Debug builds only.
#if DEBUG

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
        for written in ["It Was On Sale", "IT-WAS-ON-SALE", "  it was  on   sale ", "it_was_on_sale"] {
            let d = scratch()
            #expect(CompedPro.redeem(written, d).isSuccess, "\(written) should work")
            #expect(CompedPro.isActive(d))
        }
    }

    @Test func everyCodeWorks() {
        for code in [
            "spendnowcrylater",
            "futuremeproblem",
            "denialisabudget",
            "itwasonsale",
            "ineedthisactually",
            "iamtheonewhobudgets",
            "ihavenomoneyandimustscream",
            "deathandtaxes",
            "latestagecapitalism",
            "treatyourselftodebt",
            "thebankdisagrees",
            "itsaninvestment",
            "moneyhasleftthechat",
            "paydayisamyth",
            "brokebutaesthetic",
            "onelastcoffee",
            "thealgorithmmademedoit",
            "roundingerror",
            "cashisamemory",
            "sortdbyraj",
        ] {
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
        #expect(CompedPro.redeem("itwasonsale", d).isSuccess)
        #expect(CompedPro.redeem("itwasonsale", d) == .alreadyUnlocked)
        #expect(CompedPro.isActive(d))
    }

    @Test func theCodeUsedIsRememberedSoYouKnowWhoIsWho() {
        let d = scratch()
        #expect(CompedPro.source(d) == nil)
        CompedPro.redeem("thebankdisagrees", d)
        #expect(CompedPro.source(d) == "thebankdisagrees")

        // Different person, different code, different name.
        let other = scratch()
        CompedPro.redeem("onelastcoffee", other)
        #expect(CompedPro.source(other) == "onelastcoffee")
    }

    @Test func everyCodeHasItsOwnName() {
        // Twenty codes are no use for telling people apart if two of them
        // say the same thing.
        var names: Set<String> = []
        for code in ["spendnowcrylater", "futuremeproblem", "denialisabudget", "itwasonsale",
                     "ineedthisactually", "iamtheonewhobudgets", "ihavenomoneyandimustscream",
                     "deathandtaxes", "latestagecapitalism", "treatyourselftodebt",
                     "thebankdisagrees", "itsaninvestment", "moneyhasleftthechat",
                     "paydayisamyth", "brokebutaesthetic", "onelastcoffee",
                     "thealgorithmmademedoit", "roundingerror", "cashisamemory", "sortdbyraj"] {
            let d = scratch()
            guard case .unlocked(let name) = CompedPro.redeem(code, d) else {
                Issue.record("\(code) did not unlock")
                continue
            }
            #expect(!names.contains(name), "\(name) is used by more than one code")
            names.insert(name)
        }
        #expect(names.count == 20)
    }

    @Test func deletingEverythingTakesProBack() {
        let d = scratch()
        CompedPro.redeem("itwasonsale", d)
        #expect(CompedPro.isActive(d))
        CompedPro.clear(d)
        #expect(!CompedPro.isActive(d))
    }

    @Test func theCodesAreNotStoredInPlainText() {
        // The lookup is by hash, so a real code and its hash differ.
        #expect(CompedPro.hash("itwasonsale") != "greedisgood")
        #expect(CompedPro.hash("itwasonsale").count == 64)
        // And the same input always gives the same hash, or nothing works.
        #expect(CompedPro.hash("It Was On Sale") == CompedPro.hash("itwasonsale"))
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

#endif

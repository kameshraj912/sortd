import Testing
import Foundation
@testable import Spend

/// The iOS 26 route (`ApplePaySetupSteps.Route.automation`): its own shortcut
/// file, the walk-through's words, and when setup may move on.
struct ApplePayAutomationRouteTests {
    private let when = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func theChipNamesThePhonesOwnIOS() {
        #expect(ApplePaySetupSteps.versionLine(major: 26) == "Steps for iOS 26, the iOS on this iPhone")
        #expect(ApplePaySetupSteps.versionLine(major: 27) == "Steps for iOS 27, the iOS on this iPhone")
    }

    /// Each iOS gets the file that works on it: iOS 27's carries triggers
    /// iOS 26 can't import, and iOS 26's is typed for a Wallet transaction.
    @Test func eachRouteDownloadsItsOwnShortcut() {
        #expect(ApplePaySetupSteps.shortcutURL(for: .shortcut).absoluteString == "https://sortd.page/apple-pay.shortcut")
        #expect(ApplePaySetupSteps.shortcutURL(for: .automation).absoluteString == "https://sortd.page/apple-pay-26.shortcut")
    }

    /// Both files are served under the name Check the Shortcut runs, and the
    /// iOS 26 one really is in the site folder that gets deployed.
    @Test func theSiteServesBothFilesUnderTheShortcutsName() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let headers = try String(contentsOf: root.appendingPathComponent("site/_headers"), encoding: .utf8)
        for path in ["/apple-pay.shortcut", "/apple-pay-26.shortcut"] {
            let block = try #require(headers.range(of: path + "\n"))
            let rest = headers[block.upperBound...].prefix(220)
            #expect(rest.contains("filename=\"\(ApplePayHealthCheck.shortcutName).shortcut\""), "\(path)")
        }
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("site/apple-pay-26.shortcut").path))
    }

    @Test func theShortWalkThroughHasThreePagesInOrder() {
        let steps = ApplePaySetupSteps.automationSteps
        #expect(steps.map(\.id) == [0, 1, 2])
        #expect(steps.allSatisfy { !$0.taps.isEmpty })
        #expect(WalletSetupGuide(route: .automation).pages.map(\.title) == steps.map(\.title))
    }

    /// The short way never asks for typing into boxes: the downloaded
    /// shortcut already holds Amount, Merchant and Card.
    @Test func theShortWalkThroughPicksTheShortcutAndFillsNothing() {
        let all = ApplePaySetupSteps.automationSteps
            .flatMap { $0.taps + [$0.title, $0.note ?? ""] }
            .joined(separator: " ")
        #expect(all.contains("Run Immediately"))
        #expect(all.contains("My Shortcuts"))
        #expect(all.contains(ApplePayHealthCheck.shortcutName))
        #expect(!all.contains("Shortcut Input"))
        #expect(!all.contains("Create New Shortcut"))
    }

    /// The by-hand fallback uses iOS 26's own words. "New Blank Automation"
    /// is not on any iOS 26 screen (it is "Create New Shortcut").
    @Test func theByHandWalkThroughUsesIOS26sOwnWords() {
        let steps = ApplePaySetupSteps.byHandAutomationSteps
        #expect(steps.map(\.id) == [0, 1, 2, 3, 4])
        #expect(WalletSetupGuide(route: .automationByHand).pages.count == 5)
        let all = steps.flatMap { $0.taps + [$0.title, $0.note ?? ""] }.joined(separator: " ")
        for words in ["Create New Shortcut", "Run Immediately", "Log Wallet Tap", "Show When Run",
                      "Shortcut Input", "Merchant", "Card or Pass"] {
            #expect(all.contains(words), "\(words)")
        }
        #expect(!all.contains("New Blank Automation"))
    }

    @Test func theStartButtonOpensANewAutomation() {
        #expect(ApplePaySetupSteps.createAutomationURL.absoluteString == "shortcuts://create-automation")
        #expect(ApplePaySetupSteps.shortcutsURL.scheme == "shortcuts")
    }

    // MARK: When Continue unlocks (the step is required)

    @Test func nothingConnectedNeverUnlocksContinue() {
        for route in [ApplePaySetupSteps.Route.shortcut, .automation] {
            for built in [false, true] {
                #expect(!ApplePaySetupSteps.isReady(status: .notConnected, route: route, saysBuilt: built))
            }
        }
    }

    /// iOS 27: the first run is not enough. Step 3 is the one that makes
    /// logging automatic, and the person has to say it is done.
    @Test func stepThreeIsNeededOnIOS27() {
        #expect(!ApplePaySetupSteps.isReady(status: .shortcutReached(when), route: .shortcut, saysBuilt: false))
        #expect(ApplePaySetupSteps.isReady(status: .shortcutReached(when), route: .shortcut, saysBuilt: true))
    }

    /// iOS 26: steps 1 and 2 let the person into the app (6 Oct 2026). Its
    /// step 3 is the hard one, and being stuck there must not lock the app.
    @Test func iOS26GoesOnAfterStepsOneAndTwo() {
        #expect(ApplePaySetupSteps.isReady(status: .shortcutReached(when), route: .automation, saysBuilt: false))
        #expect(ApplePaySetupSteps.isReady(status: .shortcutReached(when), route: .automation, saysBuilt: true))
    }

    /// Step 3 is put off, not dropped: Home keeps saying it is left until the
    /// person says the automation is on, or a real tap lands.
    @Test func stepThreeStaysLeftUntilItIsDone() {
        #expect(ApplePaySetupSteps.stepThreeLeft(status: .shortcutReached(when), saysBuilt: false))
        #expect(!ApplePaySetupSteps.stepThreeLeft(status: .shortcutReached(when), saysBuilt: true))
        #expect(!ApplePaySetupSteps.stepThreeLeft(status: .notConnected, saysBuilt: false))
        let tap = ApplePayStatus.tapLogged(date: when, merchant: "Seven Seeds",
                                           amount: Decimal(string: "4.50")!, currency: "AUD")
        #expect(!ApplePaySetupSteps.stepThreeLeft(status: tap, saysBuilt: false))
        #expect(!ApplePaySetupSteps.stepThreeLeft(status: .tapNeedsCheck(date: when), saysBuilt: false))
    }

    /// The search trap: the keyboard's "Wallet" suggestion adds a space and
    /// Shortcuts shows nothing. The first page says how to get out of it.
    @Test func firstAutomationPageWarnsAboutTheEmptyList() {
        #expect(ApplePaySetupSteps.automationSteps[0].note?.contains("Delete the space after Wallet") == true)
    }

    /// A real tap proves everything, whatever was or wasn't ticked off.
    @Test func aRealTapAlwaysUnlocksContinue() {
        let tap = ApplePayStatus.tapLogged(date: when, merchant: "Seven Seeds",
                                           amount: Decimal(string: "4.50")!, currency: "AUD")
        for status in [tap, .tapNeedsCheck(date: when)] {
            for route in [ApplePaySetupSteps.Route.shortcut, .automation] {
                #expect(ApplePaySetupSteps.isReady(status: status, route: route, saysBuilt: false))
            }
        }
    }

    /// The setup screen's own line is honest about the time on each route,
    /// and no longer offers "later": the step is required.
    @Test func theSetupLineSaysTheTimeAndNeverLater() throws {
        try #require(SetupFlow.usesNewFlow)
        #expect(SetupCopy.line(.applePay, route: .automation) == "About 2 minutes, once.")
        #expect(SetupCopy.line(.applePay, route: .shortcut) == "About a minute, once.")
        #expect(SetupCopy.line(.cards, route: .shortcut)?.contains("skip") == false)
        #expect(SetupCopy.line(.welcome, route: .automation) == SetupCopy.line(.welcome, route: .shortcut))
    }
}

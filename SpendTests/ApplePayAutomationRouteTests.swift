import Testing
import Foundation
@testable import Spend

/// The iOS 26 route (`ApplePaySetupSteps.Route.automation`): what the status
/// card says while nothing is connected, and the walk-through's words. On
/// iOS 26 the ready-made shortcut can't work, so nothing here may send
/// anyone to it.
struct ApplePayAutomationRouteTests {
    private let when = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func theChipNamesThePhonesOwnIOS() {
        #expect(ApplePaySetupSteps.versionLine(major: 26) == "Steps for iOS 26, the iOS on this iPhone")
        #expect(ApplePaySetupSteps.versionLine(major: 27) == "Steps for iOS 27, the iOS on this iPhone")
    }

    /// Before the walk-through: no mention of a shortcut to get.
    @Test func notConnectedOnIOS26PointsAtTheAutomation() {
        let card = ApplePaySetupSteps.card(for: .notConnected, route: .automation, saysBuilt: false)
        #expect(card.title == "Not connected yet")
        #expect(card.detail == "Make one small automation in Shortcuts. About 2 minutes.")
        #expect(!card.detail.contains("Get the Shortcut"))
    }

    /// After "I'm Done" Sortd still knows nothing, so it waits; it never
    /// says connected.
    @Test func afterTheWalkThroughTheCardOnlyWaits() {
        let card = ApplePaySetupSteps.card(for: .notConnected, route: .automation, saysBuilt: true)
        #expect(card.title == "Waiting for your first tap")
        #expect(!card.title.lowercased().contains("connected"))
        #expect(card.detail.contains("Pay with Apple Pay in a shop"))
    }

    /// iOS 27 keeps the status's own words, whatever the "built" flag says.
    @Test func theShortcutRouteKeepsItsOwnWords() {
        for built in [false, true] {
            let card = ApplePaySetupSteps.card(for: .notConnected, route: .shortcut, saysBuilt: built)
            #expect(card.title == ApplePayStatus.notConnected.title)
            #expect(card.detail == ApplePayStatus.notConnected.detail)
        }
    }

    /// A real event always wins: once something has arrived, both routes
    /// show the status itself.
    @Test func aRealTapReadsTheSameOnBothRoutes() {
        let tap = ApplePayStatus.tapLogged(date: when, merchant: "Seven Seeds",
                                           amount: Decimal(string: "4.50")!, currency: "AUD")
        for status in [tap, .shortcutReached(when), .tapNeedsCheck(date: when)] {
            for route in [ApplePaySetupSteps.Route.shortcut, .automation] {
                let card = ApplePaySetupSteps.card(for: status, route: route, saysBuilt: true)
                #expect(card.title == status.title)
                #expect(card.detail == status.detail)
            }
        }
    }

    @Test func theWalkThroughHasFivePagesInOrder() {
        let steps = ApplePaySetupSteps.automationSteps
        #expect(steps.map(\.id) == [0, 1, 2, 3, 4])
        #expect(steps.allSatisfy { !$0.taps.isEmpty })
        #expect(WalletSetupGuide.automationPages.map(\.title) == steps.map(\.title))
    }

    /// The words are iOS 26's own. "New Blank Automation" is not on any
    /// iOS 26 screen (it is "Create New Shortcut"), and the download and its
    /// check don't exist on this route.
    @Test func theWalkThroughUsesIOS26sOwnWords() {
        let all = ApplePaySetupSteps.automationSteps
            .flatMap { $0.taps + [$0.title, $0.note ?? ""] }
            .joined(separator: " ")
        #expect(all.contains("Create New Shortcut"))
        #expect(all.contains("Run Immediately"))
        #expect(all.contains("Log Wallet Tap"))
        #expect(all.contains("Show When Run"))
        #expect(!all.contains("New Blank Automation"))
        #expect(!all.contains("Get the Shortcut"))
        #expect(!all.contains("Check the Shortcut"))
    }

    /// The three boxes are named as Sortd's action shows them, and filled
    /// with what Shortcuts calls each part of the tap.
    @Test func theThreeBoxesMatchTheActionsOwnNames() {
        let boxes = ApplePaySetupSteps.automationSteps[3].taps.joined(separator: " ")
        for word in ["Amount", "Shop", "Merchant", "Card", "Card or Pass", "Shortcut Input"] {
            #expect(boxes.contains(word), "\(word)")
        }
    }

    @Test func theStartButtonOpensANewAutomation() {
        #expect(ApplePaySetupSteps.createAutomationURL.absoluteString == "shortcuts://create-automation")
        #expect(ApplePaySetupSteps.shortcutsURL.scheme == "shortcuts")
    }

    /// The setup screen's own line is honest about the time on each route.
    @Test func theSetupLineSaysTwoMinutesOnIOS26() {
        guard SetupFlow.usesNewFlow else { return }
        #expect(SetupCopy.line(.applePay, route: .automation) == "About 2 minutes, once. Or do it later from Home.")
        #expect(SetupCopy.line(.applePay, route: .shortcut) == "About a minute, once. Or do it later from Home.")
        #expect(SetupCopy.line(.welcome, route: .automation) == SetupCopy.line(.welcome, route: .shortcut))
    }
}

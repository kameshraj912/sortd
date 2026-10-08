import Testing
import Foundation
@testable import Spend

/// The iOS 26 route (`ApplePaySetupSteps.Route.automation`): the automation
/// built by hand, the walk-through's words, and when setup may move on.
struct ApplePayAutomationRouteTests {
    private let when = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func theChipNamesThePhonesOwnIOS() {
        #expect(ApplePaySetupSteps.versionLine(major: 26) == "Steps for iOS 26, the iOS on this iPhone")
        #expect(ApplePaySetupSteps.versionLine(major: 27) == "Steps for iOS 27, the iOS on this iPhone")
    }

    /// Only iOS 27 downloads a shortcut. iOS 26 builds the step by hand:
    /// a step that arrives in a downloaded shortcut asks "Allow … to share …
    /// with Sortd?" on the first real tap, which a background automation
    /// can't show (6 Oct 2026, "Automation failed").
    @Test func onlyIOS27DownloadsAShortcut() {
        #expect(ApplePaySetupSteps.shortcutFileURL.absoluteString == "https://sortd.page/apple-pay.shortcut")
        let all = ApplePaySetupSteps.automationSteps
            .flatMap { $0.taps + [$0.title, $0.note ?? ""] }
            .joined(separator: " ")
        #expect(!all.contains("apple-pay-26"))
        #expect(!all.contains("Under them, tap " + ApplePayHealthCheck.shortcutName))
    }

    /// The iOS 27 file is served under the name Check the Shortcut runs.
    @Test func theSiteServesTheShortcutUnderTheShortcutsName() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let headers = try String(contentsOf: root.appendingPathComponent("site/_headers"), encoding: .utf8)
        let block = try #require(headers.range(of: "/apple-pay.shortcut\n"))
        let rest = headers[block.upperBound...].prefix(220)
        #expect(rest.contains("filename=\"\(ApplePayHealthCheck.shortcutName).shortcut\""))
    }

    /// The iOS 26 walk-through builds Sortd's action into the automation,
    /// in iOS 26's own words. "New Blank Automation" is not on any iOS 26
    /// screen (it is "Create New Shortcut").
    @Test func theIOS26WalkThroughBuildsTheActionByHand() {
        let steps = ApplePaySetupSteps.automationSteps
        #expect(steps.map(\.id) == [0, 1, 2, 3, 4])
        #expect(steps.allSatisfy { !$0.taps.isEmpty })
        #expect(WalletSetupGuide(route: .automation).pages.map(\.title) == steps.map(\.title))
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

    /// iOS 27 needs the shortcut to have reached Sortd first.
    @Test func nothingConnectedNeverUnlocksContinueOnIOS27() {
        for built in [false, true] {
            #expect(!ApplePaySetupSteps.isReady(status: .notConnected, route: .shortcut, saysBuilt: built))
        }
    }

    /// iOS 27: the first run is not enough. Step 3 is the one that makes
    /// logging automatic, and the person has to say it is done.
    @Test func stepThreeIsNeededOnIOS27() {
        #expect(!ApplePaySetupSteps.isReady(status: .shortcutReached(when), route: .shortcut, saysBuilt: false))
        #expect(ApplePaySetupSteps.isReady(status: .shortcutReached(when), route: .shortcut, saysBuilt: true))
    }

    /// iOS 26: nothing reaches Sortd before a real tap, so "I'm Done" at the
    /// end of the walk-through is what lets the person in.
    @Test func iOS26GoesOnWithImDone() {
        #expect(!ApplePaySetupSteps.isReady(status: .notConnected, route: .automation, saysBuilt: false))
        #expect(ApplePaySetupSteps.isReady(status: .notConnected, route: .automation, saysBuilt: true))
        #expect(!ApplePaySetupSteps.isReady(status: .shortcutReached(when), route: .automation, saysBuilt: false))
        #expect(ApplePaySetupSteps.isReady(status: .shortcutReached(when), route: .automation, saysBuilt: true))
    }

    /// After "I'm Done" on iOS 26 the status card waits for the first tap
    /// instead of saying "Not connected yet". Never on iOS 27.
    @Test func iOS26WaitsForTheFirstTapAfterImDone() {
        #expect(ApplePaySetupSteps.waitingForFirstTap(status: .notConnected, route: .automation, saysBuilt: true))
        #expect(!ApplePaySetupSteps.waitingForFirstTap(status: .notConnected, route: .automation, saysBuilt: false))
        #expect(!ApplePaySetupSteps.waitingForFirstTap(status: .notConnected, route: .shortcut, saysBuilt: true))
        #expect(!ApplePaySetupSteps.waitingForFirstTap(status: .tapNeedsCheck(date: when), route: .automation, saysBuilt: true))
    }

    /// Someone who set up iOS 26 with the downloaded shortcut and never had a
    /// tap log is asked once to make the automation the new way. A tap that
    /// already landed, iOS 27, or a second launch leave everything alone.
    @Test func oldIOS26SetupIsResetOnce() throws {
        let name = "ios26-reset-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: ApplePaySetupSteps.automationBuiltKey)
        defaults.set(2, forKey: ApplePaySetupSteps.automationPageKey)

        #expect(!ApplePaySetupSteps.resetOldIOS26Setup(route: .shortcut, hasRealTap: false, defaults: defaults))
        #expect(defaults.bool(forKey: ApplePaySetupSteps.automationBuiltKey))

        #expect(ApplePaySetupSteps.resetOldIOS26Setup(route: .automation, hasRealTap: false, defaults: defaults))
        #expect(!defaults.bool(forKey: ApplePaySetupSteps.automationBuiltKey))
        #expect(defaults.integer(forKey: ApplePaySetupSteps.automationPageKey) == 0)

        defaults.set(true, forKey: ApplePaySetupSteps.automationBuiltKey)
        #expect(!ApplePaySetupSteps.resetOldIOS26Setup(route: .automation, hasRealTap: false, defaults: defaults))
        #expect(defaults.bool(forKey: ApplePaySetupSteps.automationBuiltKey))
    }

    @Test func aTapThatLandedKeepsOldIOS26Setup() throws {
        let name = "ios26-reset-tap-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: ApplePaySetupSteps.automationBuiltKey)
        #expect(!ApplePaySetupSteps.resetOldIOS26Setup(route: .automation, hasRealTap: true, defaults: defaults))
        #expect(defaults.bool(forKey: ApplePaySetupSteps.automationBuiltKey))
    }

    /// iOS 26's Home card and status line talk about the automation, not
    /// "step 3": there is only one step on iOS 26.
    @Test func iOS26NeverSaysStepThree() {
        #expect(!ApplePaySetupSteps.stepThreeLeftLine(route: .automation).contains("step"))
        #expect(!ApplePaySetupSteps.stepThreeLeftStatusLine(route: .automation).contains("Step"))
        #expect(ApplePaySetupSteps.stepThreeLeftButton(route: .automation) == "Show Me How")
        #expect(ApplePaySetupSteps.stepThreeLeftButton(route: .shortcut) == "Finish Step 3")
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

    /// iOS 26.6 beta: Sortd can be missing from the list Shortcuts shows in a
    /// new Wallet automation (an iOS picker bug). Page 3 says what to try,
    /// and that the shortcut you build yourself is the one My Shortcuts
    /// exception. The words in "sortd.page/support" open the support page.
    @Test func actionPageSaysWhatToDoWhenSortdIsNotInTheList() throws {
        let page = try #require(ApplePaySetupSteps.automationSteps.first { $0.id == 2 })
        let note = try #require(page.note)
        #expect(note.contains("restart"))
        #expect(note.contains("My Shortcuts"))
        #expect(note.contains("sortd.page/support"))
        #expect(note.contains(ApplePaySetupSteps.missingFromListLinkText))
        #expect(ApplePaySetupSteps.missingFromListURL.absoluteString == "https://sortd.page/support#ios26-missing")
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

/// `apple_pay_setup_action`: the funnel event for the step (6 Oct 2026).
struct ApplePaySetupActionTests {
    private let when = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func progressTellsTheThreeStatesApart() {
        typealias P = ApplePaySetupSteps.Progress
        #expect(P(status: .notConnected, saysBuilt: false) == .notConnected)
        #expect(P(status: .notConnected, saysBuilt: true) == .notConnected)
        #expect(P(status: .shortcutReached(when), saysBuilt: false) == .stepThreeLeft)
        #expect(P(status: .shortcutReached(when), saysBuilt: true) == .saidDone)
        #expect(P(status: .tapNeedsCheck(date: when), saysBuilt: false) == .tapLogged)
        let tap = ApplePayStatus.tapLogged(date: when, merchant: "Seven Seeds", amount: 4.5, currency: "AUD")
        #expect(P(status: tap, saysBuilt: false) == .tapLogged)
    }

    /// The event carries the button, the route and the progress, and no
    /// shop or amount, whatever the status holds.
    @Test func theEventCarriesOnlySafeProperties() {
        #expect(Analytics.Event.applePaySetupAction.rawValue == "apple_pay_setup_action")
        let tap = ApplePayStatus.tapLogged(date: when, merchant: "Seven Seeds", amount: 4.5, currency: "AUD")
        let sink = SpySink()
        let name = "ApplePaySetupActionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let analytics = Analytics(sink: sink, defaults: defaults, regionCode: "AU")
        analytics.isEnabled = true
        analytics.track(.applePaySetupAction, ["action": .string("guide_next"), "route": .string("automation"),
                                               "step": .string(ApplePaySetupSteps.Progress(status: tap, saysBuilt: false).rawValue),
                                               "page": .int(2)])
        let sent = sink.captured.last
        #expect(sent?.name == "apple_pay_setup_action")
        #expect(Set(sent?.properties.keys.map { $0 } ?? []) == ["action", "route", "step", "page"])
        #expect(sent?.properties["step"] as? String == "tap_logged")
        #expect(analytics.violations.isEmpty)
    }

    /// Replay records only with the TestFlight receipt in a Release build;
    /// an App Store copy, or one with no receipt, never does.
    @Test func replayNeedsTheFlagAndATestFlightReceipt() {
        #expect(!Analytics.replayAllowed(flagOn: false, isTestFlight: true))
        #expect(!Analytics.replayAllowed(flagOn: false, isTestFlight: false))
        #expect(Analytics.replayAllowed(flagOn: true, isTestFlight: true))
        #if !DEBUG
        #expect(!Analytics.replayAllowed(flagOn: true, isTestFlight: false))
        #endif
        #expect(Distribution.isTestFlight(receiptName: "sandboxReceipt"))
        #expect(!Distribution.isTestFlight(receiptName: "receipt"))
        #expect(!Distribution.isTestFlight(receiptName: nil))
    }
}

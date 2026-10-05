import Foundation

/// Which of the three "add it, run it, switch it on" steps the setup panel
/// can honestly tick off, given the connection status (`applepay-guide`
/// rewrite, 27 Sep 2026 — the ready-made shortcut now carries the whole
/// automation, so all that's left by hand is running it once and flipping
/// its own switch).
///
/// Steps 1 and 3 have no event of their own: nothing tells the app "the
/// shortcut is in the library" or "the automation switch is on". So step 1
/// ticks together with step 2 — the first thing Sortd can ever see is the
/// shortcut reaching it, and that can't happen unless step 1 already
/// happened. Step 3 only ticks once a real shop tap has actually landed,
/// since a tap can only reach Sortd at all with the automation switched on.
enum ApplePaySetupSteps {
    struct Ticked: Equatable {
        let addShortcut: Bool
        let runAndAllow: Bool
        let turnOnAutomation: Bool
    }

    static func ticked(for status: ApplePayStatus) -> Ticked {
        switch status {
        case .notConnected:
            Ticked(addShortcut: false, runAndAllow: false, turnOnAutomation: false)
        case .shortcutReached:
            Ticked(addShortcut: true, runAndAllow: true, turnOnAutomation: false)
        case .tapLogged, .tapNeedsCheck:
            Ticked(addShortcut: true, runAndAllow: true, turnOnAutomation: true)
        }
    }
}

// MARK: - Online payments (2 Oct 2026)

extension ApplePaySetupSteps {
    /// Step 2's words. The shortcut runs with "Show When Run" off, so
    /// nothing appears in Shortcuts after ▶: the person comes back here and
    /// the step ticks itself from `ApplePayStatus`.
    static let runStep = (title: "Run it once and tap Allow",
                          detail: "Press ▶ in the shortcut and tap Allow. Then come back here.")

    /// Step 3's words. With iOS 27's Notification trigger the shortcut has
    /// two "When…" lines (the tap and Wallet's notification), each with its
    /// own Automation switch. Before iOS 27 there is only the tap.
    static func automationStep(notificationTrigger: Bool) -> (title: String, detail: String) {
        notificationTrigger
            ? ("Turn both automations on",
               "In the shortcut, tap › next to each \u{201C}When…\u{201D} line and switch on Automation.")
            : ("Turn the automation on",
               "In the shortcut, tap › next to \u{201C}tapped\u{201D}, then switch on Automation.")
    }

    /// The quiet line under the steps: what the shortcut can see.
    static func scopeLine(notificationTrigger: Bool) -> String {
        notificationTrigger
            ? "Taps in shops log from the tap. Payments in apps and on websites log from Wallet's notification, if your bank sends one."
            : "Works for taps in shops. Online and Apple Watch payments don't reach Shortcuts."
    }

    /// The footer under Apple Pay in Settings › Purchase Sources.
    static func sourcesFooter(notificationTrigger: Bool) -> String {
        notificationTrigger
            ? "Logs Apple Pay taps in shops the moment you pay, and online payments when Wallet sends a notification."
            : "Logs in-store Apple Pay taps the moment you pay."
    }

    /// The footer under the panel: what still needs adding by hand.
    static func byHandLine(notificationTrigger: Bool) -> String {
        notificationTrigger
            ? "Anything the shortcut misses, add by hand with +."
            : "Add in-app and online Apple Pay by hand."
    }

    /// Where Get the Shortcut goes: our own signed shortcut file (built by
    /// `scripts/build-apple-pay-shortcut.py`). It opens in Sortd's in-app
    /// Safari sheet, never through `openURL`: with Chrome as the default
    /// browser the link showed a blank page (4 Oct 2026).
    static let shortcutURL = URL(string: "https://sortd.page/apple-pay.shortcut")!
}

// MARK: - iOS 26: the automation is built by hand (5 Oct 2026)

extension ApplePaySetupSteps {
    /// How this iPhone connects Apple Pay. The setup screen shows one route
    /// only, picked from the iOS it is running on.
    enum Route: Equatable {
        /// iOS 27: the ready-made shortcut carries its own triggers.
        case shortcut
        /// iOS 26: a shared shortcut can't carry a Wallet trigger, and on
        /// import it loses its Amount and Merchant mappings (a library
        /// shortcut can't take a Transaction as input; checked on the 26.5
        /// simulator, 5 Oct 2026). So the person makes a personal automation
        /// in Shortcuts, and Get the Shortcut and Check the Shortcut, which
        /// can never work there, are not offered.
        case automation
    }

    static var route: Route {
        #if DEBUG
        // SPEND_SETUP_ROUTE=automation shows the iOS 26 screens on any simulator.
        if let forced = ProcessInfo.processInfo.environment["SPEND_SETUP_ROUTE"] {
            return forced == "automation" ? .automation : .shortcut
        }
        #endif
        if #available(iOS 27.0, *) { return .shortcut }
        return .automation
    }

    /// "Steps for iOS 26, the iOS on this iPhone": says out loud that the
    /// steps were picked for this phone, so nobody wonders which guide to follow.
    static func versionLine(major: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) -> String {
        "Steps for iOS \(major), the iOS on this iPhone"
    }

    /// One page of the iOS 26 walk-through.
    struct AutomationStep: Identifiable, Equatable {
        let id: Int
        let title: String
        /// One thing to do per line, in order. The numbers match the rings
        /// in the page's drawing (`ShortcutsMock`, route `.automation`).
        let taps: [String]
        var note: String?
    }

    /// The walk-through, in the words iOS 26 itself uses (read from the
    /// 26.0, 26.4 and 26.5 simulators' Shortcuts on 5 Oct 2026: the row is
    /// "Create New Shortcut", not "New Blank Automation").
    static let automationSteps: [AutomationStep] = [
        AutomationStep(id: 0, title: "Choose Wallet",
                       taps: ["Tap Search at the bottom and type Wallet.",
                              "Tap Wallet."],
                       note: "See your shortcuts instead? Tap Automation at the bottom, then New Automation."),
        AutomationStep(id: 1, title: "Tick your cards",
                       taps: ["Tick every card you pay with.",
                              "Tap Run Immediately.",
                              "Tap Next."]),
        AutomationStep(id: 2, title: "Add Sortd's action",
                       taps: ["Tap Create New Shortcut.",
                              "Scroll down and tap Sortd.",
                              "Tap Log Wallet Tap."]),
        AutomationStep(id: 3, title: "Fill in 3 boxes",
                       taps: ["Tap Amount, then Shortcut Input above the keyboard. Tap Shortcut Input again and choose Amount.",
                              "Do the same for Shop. Choose Merchant.",
                              "Tap the blue ›, then Card. Choose Card or Pass."]),
        AutomationStep(id: 4, title: "Turn off Show When Run",
                       taps: ["Switch off Show When Run. It is under Card.",
                              "Tap Done at the top right."],
                       note: "You only do this once."),
    ]

    /// Opens Shortcuts on its "new automation" list, past Automation › New
    /// Automation (present in iOS 26.0 to 26.5). If a future iOS drops it,
    /// Shortcuts still opens and the first page's note covers the two taps.
    static let createAutomationURL = URL(string: "shortcuts://create-automation")!
    /// Back to Shortcuts, wherever it was left.
    static let shortcutsURL = URL(string: "shortcuts://")!

    /// Set when the person taps "I'm Done" on the last page. Nothing tells
    /// Sortd an automation exists, so this is only ever worded as waiting.
    static let automationBuiltKey = "applePayAutomationBuilt"
    /// The page the walk-through was left on, so a trip to Shortcuts and
    /// back (or a relaunch) lands where the person was.
    static let automationPageKey = "applePayAutomationPage"

    /// The status card's two lines. Only "not connected" differs by route:
    /// on iOS 26 there is no shortcut to get, and after "I'm Done" the card
    /// waits for a real tap rather than claiming anything.
    static func card(for status: ApplePayStatus, route: Route, saysBuilt: Bool) -> (title: String, detail: String) {
        guard status == .notConnected, route == .automation else { return (status.title, status.detail) }
        return saysBuilt
            ? ("Waiting for your first tap", "Pay with Apple Pay in a shop. It shows up here and in Activity.")
            : ("Not connected yet", "Make one small automation in Shortcuts. About 2 minutes.")
    }

    /// Under the walk-through button once it has been finished.
    static let automationTestLine = "The ▶ button in Shortcuts can't test this. A real tap in a shop is the test."
}

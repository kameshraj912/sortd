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
    ///
    /// After Add Shortcut the person lands in the Shortcuts library, where
    /// there is no ▶ (it is inside the shortcut, behind ···). Tapping the
    /// shortcut there runs it, so that is what the words say (6 Oct 2026,
    /// a full run on the iOS 26.5 simulator).
    static let runStep = (title: "Run it once and tap Allow",
                          detail: "In Shortcuts, tap Log Apple Pay in Sortd to run it (or press ▶ if it is open). Tap Allow, then come back here.")

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

// MARK: - iOS 26: the person makes the automation (5 Oct 2026)

extension ApplePaySetupSteps {
    /// How this iPhone connects Apple Pay. The setup screen shows one route
    /// only, picked from the iOS it is running on.
    enum Route: Equatable {
        /// iOS 27: the ready-made shortcut carries its own triggers; the
        /// person switches them on.
        case shortcut
        /// iOS 26: a shortcut can't bring an automation with it. The person
        /// adds the iOS 26 shortcut (`shortcutURL(for:)`), runs it once, then
        /// makes a Wallet automation and picks that shortcut in it. Check the
        /// Shortcut, which sends text, is not offered: this shortcut only
        /// takes a Wallet transaction.
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

    /// The file Get the Shortcut opens. iOS 26 has its own: no triggers, and
    /// its input typed as a Wallet transaction so Amount, Merchant and Card
    /// survive the import (`scripts/build-apple-pay-shortcut.py --ios26`).
    static func shortcutURL(for route: Route) -> URL {
        #if DEBUG
        // A local copy, for simulator runs before the site has the file.
        if let forced = ProcessInfo.processInfo.environment["SPEND_SHORTCUT_URL"], let url = URL(string: forced) { return url }
        #endif
        return route == .shortcut ? shortcutURL : URL(string: "https://sortd.page/apple-pay-26.shortcut")!
    }

    /// Step 3 on iOS 26.
    static let makeAutomationStep = (title: "Tell Shortcuts when to run it",
                                     detail: "Make one automation, so it runs each time you pay. We show you every tap.")

    /// One page of a walk-through.
    struct AutomationStep: Identifiable, Equatable {
        let id: Int
        let title: String
        /// One thing to do per line, in order. The numbers match the rings
        /// in the page's drawing (`ShortcutsMock`).
        let taps: [String]
        var note: String?
    }

    /// The iOS 26 walk-through: the automation that runs the downloaded
    /// shortcut. Words are iOS 26's own, read from the 26.0, 26.4 and 26.5
    /// simulators' Shortcuts on 5 Oct 2026. Short lines, one tap each:
    /// written for someone who has never opened Shortcuts.
    static let automationSteps: [AutomationStep] = [
        AutomationStep(id: 0, title: "Find Wallet",
                       taps: ["Tap the Search box at the bottom. Type the word Wallet.",
                              "Tap Wallet in the list."],
                       // The keyboard's own "Wallet" suggestion adds a space, and
                       // Shortcuts then shows an empty list (iOS 26.5, 6 Oct 2026).
                       note: "List went empty? Delete the space after Wallet.\nDon't see a Search box? Tap Automation at the bottom, then New Automation."),
        AutomationStep(id: 1, title: "Choose your cards",
                       taps: ["Tap each card you pay with. A tick shows beside it.",
                              "Tap Run Immediately.",
                              "Tap Next at the top right."]),
        AutomationStep(id: 2, title: "Pick the Sortd shortcut",
                       taps: ["Find the words My Shortcuts.",
                              "Under them, tap Log Apple Pay in Sortd."],
                       note: "That is all. Nothing to type."),
    ]

    /// The long way on iOS 26, for when the downloaded shortcut doesn't log
    /// a tap: the action is added and filled in by hand. This is the route
    /// Raj's own printed guide walks through.
    static let byHandAutomationSteps: [AutomationStep] = [
        automationSteps[0],
        automationSteps[1],
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
    /// Sortd an automation exists, so this only ever means "they say so".
    static let automationBuiltKey = "applePayAutomationBuilt"
    /// The page the walk-through was left on, so a trip to Shortcuts and
    /// back (or a relaunch) lands where the person was.
    static let automationPageKey = "applePayAutomationPage"

    /// Whether setup may move on from the Apple Pay step. Steps 1 and 2 show
    /// as the shortcut reaching Sortd. Step 3 can't be seen, so the person
    /// says so: "I'm Done" on the iOS 26 pages, "I Switched Both On" on iOS
    /// 27. A real tap proves all three.
    ///
    /// iOS 27 needs all three (Raj, 5 Oct 2026: people tapped Continue past
    /// them, and step 3 is the one that makes logging automatic; there it is
    /// two switches). iOS 26 lets people in after steps 1 and 2 (Raj, 6 Oct
    /// 2026): its step 3 is about seven taps in Shortcuts, from memory, and
    /// testers who got stuck there were locked out of the whole app. Step 3
    /// is not dropped: `stepThreeLeft` keeps it on Home until it is done.
    static func isReady(status: ApplePayStatus, route: Route, saysBuilt: Bool) -> Bool {
        switch status {
        case .notConnected: false
        case .shortcutReached: route == .automation || saysBuilt
        case .tapLogged, .tapNeedsCheck: true
        }
    }

    /// Steps 1 and 2 are done and step 3 is not: the shortcut has reached
    /// Sortd, no real tap has landed, and the person hasn't said the
    /// automation is on. Until it is, no tap is written down.
    static func stepThreeLeft(status: ApplePayStatus, saysBuilt: Bool) -> Bool {
        if case .shortcutReached = status { return !saysBuilt }
        return false
    }

    /// The status card on the setup page while step 3 is left. "Now pay in a
    /// shop" would be a lie there: nothing logs until the automation exists.
    static let stepThreeLeftStatusLine = "Steps 1 and 2 are done. Step 3 is left, and it is the one that logs your taps."

    /// The Home card for `stepThreeLeft`.
    static let stepThreeLeftTitle = "Apple Pay isn't logging yet"
    static let stepThreeLeftLine = "One step is left in Shortcuts. Until it's done, your taps aren't written down."

    /// Under step 3 once the walk-through is finished and no tap has landed.
    static let automationTestLine = "Now pay with Apple Pay in a shop. The purchase shows up in Sortd by itself."
}

// MARK: - What people tap on the step (6 Oct 2026)

extension ApplePaySetupSteps {
    /// Where the Apple Pay setup had got to, for `apple_pay_setup_action`.
    /// `ApplePayStatus` plus the person's own "I'm done": the three things
    /// the funnel needs to tell apart. Never an amount or a shop.
    enum Progress: String {
        /// Nothing has reached Sortd.
        case notConnected = "not_connected"
        /// The shortcut ran (steps 1 and 2), step 3 not said done.
        case stepThreeLeft = "step_3_left"
        /// Step 3 said done, no real tap yet.
        case saidDone = "said_done"
        /// A real tap has landed.
        case tapLogged = "tap_logged"

        init(status: ApplePayStatus, saysBuilt: Bool) {
            switch status {
            case .notConnected: self = .notConnected
            case .shortcutReached: self = saysBuilt ? .saidDone : .stepThreeLeft
            case .tapLogged, .tapNeedsCheck: self = .tapLogged
            }
        }
    }

    /// One event per tap on the step, so the funnel shows where people
    /// stop. `action` is the button's name in snake case; `page` is the
    /// walk-through page for `guide_page`, 1-based.
    static func trackAction(_ action: String, route: Route = ApplePaySetupSteps.route,
                            status: ApplePayStatus, saysBuilt: Bool, page: Int? = nil) {
        // Sample data is a look around, not a setup: keep it out of the funnel.
        guard !DemoData.isActive else { return }
        var props: [String: Analytics.AnalyticsValue] = [
            "action": .string(action),
            "route": .string(route == .shortcut ? "shortcut" : "automation"),
            "step": .string(Progress(status: status, saysBuilt: saysBuilt).rawValue),
        ]
        if let page { props["page"] = .int(page) }
        Analytics.shared.track(.applePaySetupAction, props)
    }
}

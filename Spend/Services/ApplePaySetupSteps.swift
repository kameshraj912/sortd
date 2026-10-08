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

    /// The quiet line under the steps: what the shortcut can see. On iOS 27
    /// a payment in an app or on a website can come from Wallet's
    /// notification or, once the person adds it, their bank app's (8 Oct 2026).
    static func scopeLine(notificationTrigger: Bool) -> String {
        notificationTrigger
            ? "Taps in shops log from the tap. Payments in apps and on websites log from a notification, from Wallet or from your bank's app."
            : "Works for taps in shops. Online and Apple Watch payments don't reach Shortcuts."
    }

    /// The footer under Apple Pay in Settings › Purchase Sources.
    static func sourcesFooter(notificationTrigger: Bool) -> String {
        notificationTrigger
            ? "Logs Apple Pay taps in shops the moment you pay, and other payments when Wallet or your bank's app sends a notification."
            : "Logs in-store Apple Pay taps the moment you pay."
    }

    /// Under the scope line on iOS 27 only. Some banks (ANZ, CommBank) send
    /// Wallet no notification for in-app Apple Pay, and sometimes none for a
    /// tap, but their own app does (8 Oct 2026).
    static let bankAppLine = "Bank doesn't send Wallet a notification? In the shortcut, tap + next to Wallet under \u{201C}When I receive a notification\u{201D} and add your bank's app. Turn on purchase alerts in that app."

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
        /// iOS 26: a shortcut can't bring an automation with it, so the
        /// person builds one in Shortcuts: a Wallet automation with Sortd's
        /// Log Wallet Tap inside it, filled from the tap (`automationSteps`).
        /// Nothing is downloaded (6 Oct 2026): a step that arrives in a
        /// downloaded shortcut needs a second "Allow … to share … with
        /// Sortd?" the first time a real tap's data reaches it, and an
        /// automation runs in the background where that question can't be
        /// shown, so every tap ended in "Automation failed". A step added by
        /// hand is trusted from the start (checked on the iOS 26.5
        /// simulator). Check the Shortcut is not offered: there is no
        /// shortcut of ours to run.
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

    /// The file Get the Shortcut opens (iOS 27 only; iOS 26 downloads nothing).
    static var shortcutFileURL: URL {
        #if DEBUG
        // A local copy, for simulator runs before the site has the file.
        if let forced = ProcessInfo.processInfo.environment["SPEND_SHORTCUT_URL"], let url = URL(string: forced) { return url }
        #endif
        return shortcutURL
    }

    /// The one step on iOS 26: the automation, built by hand.
    static let makeAutomationStep = (title: "Make one automation in Shortcuts",
                                     detail: "5 short steps, about 2 minutes. You do it once. After that, every Apple Pay tap in a shop logs by itself.")

    /// One page of a walk-through.
    struct AutomationStep: Identifiable, Equatable {
        let id: Int
        let title: String
        /// One thing to do per line, in order. The numbers match the rings
        /// in the page's drawing (`ShortcutsMock`).
        let taps: [String]
        var note: String?
    }

    /// The iOS 26 walk-through: a Wallet automation with Sortd's action
    /// added and filled in by hand. Words are iOS 26's own, read from the
    /// 26.0, 26.4 and 26.5 simulators' Shortcuts on 5 Oct 2026. Short lines,
    /// one tap each: written for someone who has never opened Shortcuts.
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
        AutomationStep(id: 2, title: "Add Sortd's action",
                       taps: ["Tap Create New Shortcut.",
                              "Scroll down and tap Sortd.",
                              "Tap Log Wallet Tap."],
                       // iOS 26.6 beta: Sortd was missing from this list for one tester
                       // (an iOS picker bug, 8 Oct 2026). A shortcut built by hand is
                       // trusted; a downloaded one is not, so the fallback is the one
                       // time My Shortcuts is right (`missingFromListURL`).
                       note: "Don't pick a shortcut under My Shortcuts. Sortd's own action is the one that works.\nSortd not in the list? Open Sortd once, wait ten seconds, then restart your iPhone and try again. Still missing? Build it yourself first: see \u{201C}Sortd isn't in the list\u{201D} on sortd.page/support."),
        AutomationStep(id: 3, title: "Fill in 3 boxes",
                       taps: ["Tap Amount, then Shortcut Input above the keyboard. Tap Shortcut Input again and choose Amount.",
                              "Do the same for Shop. Choose Merchant.",
                              "Tap the blue ›, then Card. Choose Shortcut Input, then Card or Pass."]),
        AutomationStep(id: 4, title: "Turn off Show When Run",
                       taps: ["Switch off Show When Run. It is under Card.",
                              "Tap Done at the top right."],
                       note: "That's it. Now pay with Apple Pay in a shop."),
    ]

    /// Set up with an older build: the Wallet automation runs the downloaded
    /// "Log Apple Pay in Sortd", which can't log a tap. Said on the first page
    /// for anyone who made one.
    static let oldAutomationLine = "Made a Wallet automation for Sortd before? Delete it first: in Automation, swipe left on it and tap Delete."

    /// Opens Shortcuts on its "new automation" list, past Automation › New
    /// Automation (present in iOS 26.0 to 26.5). If a future iOS drops it,
    /// Shortcuts still opens and the first page's note covers the two taps.
    static let createAutomationURL = URL(string: "shortcuts://create-automation")!
    /// Back to Shortcuts, wherever it was left.
    static let shortcutsURL = URL(string: "shortcuts://")!
    /// The support page's fallback for "Sortd isn't in the Shortcuts list"
    /// (opened in the in-app Safari sheet from page 3's note).
    static let missingFromListURL = URL(string: "https://sortd.page/support#ios26-missing")!
    /// The words in a note that open `missingFromListURL`.
    static let missingFromListLinkText = "sortd.page/support"

    /// Set when the person taps "I'm Done" on the last page. Nothing tells
    /// Sortd an automation exists, so this only ever means "they say so".
    static let automationBuiltKey = "applePayAutomationBuilt"
    /// The page the walk-through was left on, so a trip to Shortcuts and
    /// back (or a relaunch) lands where the person was.
    static let automationPageKey = "applePayAutomationPage"

    /// Whether setup may move on from the Apple Pay step. A real tap proves
    /// everything. Otherwise the person says the automation is made, since
    /// Sortd can't see it: "I Switched Both On" on iOS 27 (after the
    /// shortcut has reached Sortd), "I'm Done" at the end of the iOS 26
    /// walk-through, where nothing reaches Sortd before a real tap.
    ///
    /// iOS 27 needs all three steps (Raj, 5 Oct 2026: people tapped
    /// Continue past them). iOS 26's walk-through can be paged to its end,
    /// so being stuck in Shortcuts never locks anyone out of the app.
    static func isReady(status: ApplePayStatus, route: Route, saysBuilt: Bool) -> Bool {
        switch status {
        case .tapLogged, .tapNeedsCheck: true
        case .shortcutReached: saysBuilt
        case .notConnected: route == .automation && saysBuilt
        }
    }

    /// iOS 26 after "I'm Done", before the first real tap: nothing has
    /// reached Sortd yet, and that is expected. The status card says so
    /// instead of "Not connected yet".
    static func waitingForFirstTap(status: ApplePayStatus, route: Route = ApplePaySetupSteps.route, saysBuilt: Bool) -> Bool {
        route == .automation && saysBuilt && status == .notConnected
    }

    /// The status card for `waitingForFirstTap`.
    static let waitingTitle = "Ready for your first tap"
    static let waitingDetail = "Pay with Apple Pay in a shop. It shows up here by itself."
    /// iOS 26, nothing made yet.
    static let notSetUpDetail = "Make the automation below. Until then, your taps aren't written down."

    /// Steps 1 and 2 are done and step 3 is not: the shortcut has reached
    /// Sortd, no real tap has landed, and the person hasn't said the
    /// automation is on. Until it is, no tap is written down.
    static func stepThreeLeft(status: ApplePayStatus, saysBuilt: Bool) -> Bool {
        if case .shortcutReached = status { return !saysBuilt }
        return false
    }

    /// The status card on the setup page while step 3 is left. "Now pay in a
    /// shop" would be a lie there: nothing logs until the automation exists.
    /// On iOS 26 this is someone who set up with an older build: the
    /// downloaded shortcut reached Sortd, but its automation can't log.
    static func stepThreeLeftStatusLine(route: Route = ApplePaySetupSteps.route) -> String {
        route == .automation
            ? "Your taps aren't logging yet. Make the automation below, the new way."
            : "Steps 1 and 2 are done. Step 3 is left, and it is the one that logs your taps."
    }

    /// The Home card for `stepThreeLeft`.
    static let stepThreeLeftTitle = "Apple Pay isn't logging yet"
    static func stepThreeLeftLine(route: Route = ApplePaySetupSteps.route) -> String {
        route == .automation
            ? "One automation to make in Shortcuts. Until it's done, your taps aren't written down."
            : "One step is left in Shortcuts. Until it's done, your taps aren't written down."
    }
    static func stepThreeLeftButton(route: Route = ApplePaySetupSteps.route) -> String {
        route == .automation ? "Show Me How" : "Finish Step 3"
    }

    /// Set once the one-time iOS 26 reset has run (`resetOldIOS26Setup`).
    static let ios26ResetKey = "applePayIOS26ByHandReset"

    /// One time, on iOS 26: anyone who said "I'm Done" on the old
    /// pick-the-shortcut walk-through and has never had a tap log made an
    /// automation that can't log. Their "done" is taken back so the setup
    /// page and Home ask them to make it the new way. Someone a tap has
    /// already reached is left alone. Returns whether it reset anything.
    @discardableResult
    static func resetOldIOS26Setup(route: Route = ApplePaySetupSteps.route, hasRealTap: Bool, defaults: UserDefaults = .standard) -> Bool {
        guard route == .automation, !defaults.bool(forKey: ios26ResetKey) else { return false }
        defaults.set(true, forKey: ios26ResetKey)
        guard !hasRealTap, defaults.bool(forKey: automationBuiltKey) else { return false }
        defaults.set(false, forKey: automationBuiltKey)
        defaults.set(0, forKey: automationPageKey)
        return true
    }

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

// MARK: - The new shortcut, and what's new for iOS 26 (8 Oct 2026)

extension ApplePaySetupSteps {
    /// The downloaded shortcut's version. 2 is build 10's (it passes the
    /// sending app and takes a bank's app on the notification trigger); 1 is
    /// builds 4 to 9's. On iOS 26 it stands for "has seen the way round
    /// Sortd missing from the Shortcuts list".
    static let shortcutVersion = 2
    /// The version this install has. Set to `shortcutVersion` when Get the
    /// Shortcut opens the file on iOS 27, on "I've Done It" on the card, and
    /// at the first launch of a fresh install (`settleShortcutVersion`).
    static let shortcutVersionKey = "applePayShortcutVersion"

    /// The stored version as it should be read. An install that set up
    /// before the key existed has the old setup, so an unset 0 reads as 1.
    static func storedShortcutVersion(raw: Int, hasSetUpBefore: Bool) -> Int {
        raw > 0 ? raw : (hasSetUpBefore ? 1 : 0)
    }

    static func storedShortcutVersion(hasSetUpBefore: Bool, defaults: UserDefaults = .standard) -> Int {
        storedShortcutVersion(raw: defaults.integer(forKey: shortcutVersionKey), hasSetUpBefore: hasSetUpBefore)
    }

    static func markNewShortcut(defaults: UserDefaults = .standard) {
        defaults.set(shortcutVersion, forKey: shortcutVersionKey)
    }

    /// At launch: an install with nothing set up and no version yet is new
    /// as of this build, so anything it sets up is the new way. Stamping it
    /// now keeps the card from showing after an iOS 26 "I'm Done" or an
    /// iOS 27 by-hand build. Returns whether it stamped.
    @discardableResult
    static func settleShortcutVersion(hasSetUpBefore: Bool, defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: shortcutVersionKey) == nil, !hasSetUpBefore else { return false }
        markNewShortcut(defaults: defaults)
        return true
    }

    /// Whether to show the card on Home and the banner on the setup page.
    ///
    /// iOS 27: the shortcut has reached Sortd before (a run or a tap row),
    /// so the old shortcut is in the library. iOS 26: setup was finished
    /// before ("I'm Done", or the old shortcut reached Sortd), and no real
    /// tap has logged; someone whose taps log needs no way round.
    static func needsNewShortcut(route: Route, hasReachedBefore: Bool, saysBuilt: Bool = false, hasRealTap: Bool = false,
                                 storedVersion: Int, dismissed: Bool) -> Bool {
        guard storedVersion < shortcutVersion, !dismissed else { return false }
        switch route {
        case .shortcut: return hasReachedBefore
        case .automation: return (saysBuilt || hasReachedBefore) && !hasRealTap
        }
    }

    /// `needsNewShortcut` from what the views hold: the status, "I'm done",
    /// and the raw stored version.
    static func needsNewShortcut(route: Route, status: ApplePayStatus, saysBuilt: Bool, rawVersion: Int) -> Bool {
        let realTap = switch status {
        case .tapLogged, .tapNeedsCheck: true
        case .notConnected, .shortcutReached: false
        }
        let setUp = status.isConnected || saysBuilt
        return needsNewShortcut(route: route, hasReachedBefore: status.isConnected, saysBuilt: saysBuilt, hasRealTap: realTap,
                                storedVersion: storedShortcutVersion(raw: rawVersion, hasSetUpBefore: setUp),
                                dismissed: false)
    }

    /// The card's words, per route.
    struct NewShortcutCopy: Equatable {
        let title: String
        let line: String
        let steps: [String]
        /// The setup page's filled button: opens a page in the Safari sheet.
        let pageButton: String
        /// Home's filled button: opens the setup page.
        let homeButton: String
        let doneButton: String
    }

    static func newShortcutCopy(route: Route) -> NewShortcutCopy {
        switch route {
        case .shortcut:
            NewShortcutCopy(
                title: "Get the new shortcut",
                line: "This build reads your bank's alerts too, so Apple Pay in apps can log even when Wallet says nothing. It needs the new shortcut.",
                steps: ["In Shortcuts, press and hold Log Apple Pay in Sortd, then Delete.",
                        "Get the shortcut again below and turn both automations on.",
                        "Tap + next to Wallet under \u{201C}When I receive a notification\u{201D} and add your bank's app. Turn on purchase alerts in that app."],
                pageButton: "Get the Shortcut",
                homeButton: "Show Me How",
                doneButton: "I've Done It")
        case .automation:
            NewShortcutCopy(
                title: "What's new for iOS 26",
                line: "If Sortd wasn't in the Shortcuts list when you made the automation, there is a way round now.",
                steps: ["Open Sortd once, wait ten seconds, then restart your iPhone and try the automation again.",
                        "Still missing? Build the shortcut first under My Shortcuts, then pick it in the Wallet automation.",
                        "The full steps are on sortd.page/support under \u{201C}Sortd isn't in the list\u{201D}."],
                pageButton: "Open the Steps",
                homeButton: "Show Me How",
                doneButton: "I've Done It")
        }
    }

    /// `apple_pay_setup_action`'s `action` for the card.
    enum NewShortcutAction {
        case shown, get, done

        func name(route: Route) -> String {
            switch (route, self) {
            case (.shortcut, .shown): "new_shortcut_shown"
            case (.shortcut, .get): "new_shortcut_get"
            case (.shortcut, .done): "new_shortcut_done"
            case (.automation, .shown): "ios26_whats_new_shown"
            case (.automation, .get): "ios26_whats_new_open"
            case (.automation, .done): "ios26_whats_new_done"
            }
        }
    }

    /// `shown` goes once per launch, whichever of the card or the banner
    /// appears first.
    private static var newShortcutShownSent = false

    /// True the first time only; flips `sent`. Pure, for the test.
    static func claimShownOnce(_ sent: inout Bool) -> Bool {
        guard !sent else { return false }
        sent = true
        return true
    }

    static func trackNewShortcut(_ action: NewShortcutAction, route: Route = ApplePaySetupSteps.route,
                                 status: ApplePayStatus, saysBuilt: Bool) {
        if action == .shown, !claimShownOnce(&newShortcutShownSent) { return }
        trackAction(action.name(route: route), route: route, status: status, saysBuilt: saysBuilt)
    }
}

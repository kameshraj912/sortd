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

    /// Where Get the Shortcut goes: the iCloud link to the same signed
    /// shortcut as `sortd.page/apple-pay.shortcut`. The Shortcuts app opens
    /// this link itself, whatever the default browser is. A plain file link
    /// opened in Chrome showed a blank page, and in Safari it needed a
    /// download first (checked on an iPhone 17 Pro, iOS 27, 4 Oct 2026).
    /// When the shortcut is rebuilt, share the new one from Shortcuts and
    /// put its iCloud link here and on `site/support.html`.
    static let shortcutURL = URL(string: "https://www.icloud.com/shortcuts/e8269fbf559d4369b96fe88ba0d60ec6")!

    /// Set the first time Get the Shortcut is tapped in a build whose
    /// shortcut carries the notification trigger.
    static let gotOnlineShortcutKey = "applePayGotOnlineShortcut"

    static let updateLine = "Updated 2 Oct: get it again to log online payments too."

    /// A shortcut added before 2 Oct only has the tap trigger. Once it is
    /// connected, say so under step 1 until Get the Shortcut is tapped again.
    static func showsUpdateLine(status: ApplePayStatus, gotNewShortcut: Bool) -> Bool {
        status.isConnected && !gotNewShortcut
    }
}

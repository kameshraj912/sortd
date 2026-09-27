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

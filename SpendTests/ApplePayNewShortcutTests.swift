import Testing
import Foundation
@testable import Spend

/// "Get the new shortcut" / "What's new for iOS 26" (8 Oct 2026). On iOS 27,
/// build 10's shortcut passes the sending app and takes a bank's app on the
/// notification trigger, so anyone whose shortcut reached Sortd on builds 4
/// to 9 is told to swap it. On iOS 26, anyone who set up before this build
/// is told the way round "Sortd isn't in the list".
struct ApplePayNewShortcutTests {
    typealias Steps = ApplePaySetupSteps

    private func defaults() -> UserDefaults {
        let name = "ApplePayNewShortcutTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func theCurrentShortcutIsVersionTwo() {
        #expect(Steps.shortcutVersion == 2)
        #expect(Steps.shortcutVersionKey == "applePayShortcutVersion")
    }

    // MARK: - iOS 27

    @Test func iOS27ShowsWhenTheOldShortcutReachedSortd() {
        #expect(Steps.needsNewShortcut(route: .shortcut, hasReachedBefore: true, storedVersion: 1, dismissed: false))
        // Taps logging through the old shortcut still need the new one.
        #expect(Steps.needsNewShortcut(route: .shortcut, hasReachedBefore: true, saysBuilt: true, hasRealTap: true,
                                       storedVersion: 1, dismissed: false))
    }

    @Test func iOS27HidesOnceTheNewShortcutIsIn() {
        #expect(!Steps.needsNewShortcut(route: .shortcut, hasReachedBefore: true, storedVersion: 2, dismissed: false))
    }

    @Test func iOS27HidesWhenDismissed() {
        #expect(!Steps.needsNewShortcut(route: .shortcut, hasReachedBefore: true, storedVersion: 1, dismissed: true))
    }

    /// A fresh install: nothing has reached Sortd, so there is no old shortcut.
    @Test func iOS27NeverShowsWhenNothingHasReachedSortd() {
        #expect(!Steps.needsNewShortcut(route: .shortcut, hasReachedBefore: false, storedVersion: 0, dismissed: false))
        #expect(!Steps.needsNewShortcut(route: .shortcut, hasReachedBefore: false, storedVersion: 1, dismissed: false))
    }

    // MARK: - iOS 26

    /// Said "I'm Done" before this build, no tap yet: shown.
    @Test func iOS26ShowsForSomeoneWhoFinishedSetupBefore() {
        #expect(Steps.needsNewShortcut(route: .automation, hasReachedBefore: false, saysBuilt: true,
                                       storedVersion: 1, dismissed: false))
        // The old downloaded shortcut reached Sortd, nothing logged.
        #expect(Steps.needsNewShortcut(route: .automation, hasReachedBefore: true, saysBuilt: false,
                                       storedVersion: 1, dismissed: false))
    }

    /// Taps already log: the automation works, nothing to tell them.
    @Test func iOS26SkipsSomeoneWhoseTapsAlreadyLog() {
        #expect(!Steps.needsNewShortcut(route: .automation, hasReachedBefore: true, saysBuilt: true, hasRealTap: true,
                                        storedVersion: 1, dismissed: false))
    }

    @Test func iOS26NeverShowsOnAFreshInstall() {
        #expect(!Steps.needsNewShortcut(route: .automation, hasReachedBefore: false, saysBuilt: false,
                                        storedVersion: 0, dismissed: false))
    }

    @Test func iOS26HidesAfterDoneOrDismiss() {
        #expect(!Steps.needsNewShortcut(route: .automation, hasReachedBefore: false, saysBuilt: true,
                                        storedVersion: 2, dismissed: false))
        #expect(!Steps.needsNewShortcut(route: .automation, hasReachedBefore: false, saysBuilt: true,
                                        storedVersion: 1, dismissed: true))
    }

    // MARK: - The stored version

    /// An install that set up before the key existed has the old setup.
    @Test func anUnsetVersionReadsAsOneOnceSetUpBefore() {
        let defaults = defaults()
        #expect(Steps.storedShortcutVersion(hasSetUpBefore: true, defaults: defaults) == 1)
        #expect(Steps.needsNewShortcut(route: .shortcut, hasReachedBefore: true,
                                       storedVersion: Steps.storedShortcutVersion(hasSetUpBefore: true, defaults: defaults),
                                       dismissed: false))
    }

    /// A fresh install taps Get the Shortcut: version 2, and it stays 2 after
    /// the shortcut reaches Sortd, so the card never shows.
    @Test func gettingTheShortcutStoresTheNewVersion() {
        let defaults = defaults()
        #expect(Steps.storedShortcutVersion(hasSetUpBefore: false, defaults: defaults) == 0)
        Steps.markNewShortcut(defaults: defaults)
        #expect(defaults.integer(forKey: Steps.shortcutVersionKey) == 2)
        #expect(Steps.storedShortcutVersion(hasSetUpBefore: false, defaults: defaults) == 2)
        #expect(Steps.storedShortcutVersion(hasSetUpBefore: true, defaults: defaults) == 2)
        #expect(!Steps.needsNewShortcut(route: .shortcut, hasReachedBefore: true,
                                        storedVersion: Steps.storedShortcutVersion(hasSetUpBefore: true, defaults: defaults),
                                        dismissed: false))
    }

    /// "I've Done It" on an old install hides the card.
    @Test func doneOnAnOldInstallHidesTheCard() {
        let defaults = defaults()
        #expect(Steps.storedShortcutVersion(hasSetUpBefore: true, defaults: defaults) == 1)
        Steps.markNewShortcut(defaults: defaults)
        #expect(Steps.storedShortcutVersion(hasSetUpBefore: true, defaults: defaults) == 2)
    }

    @Test func thePureReadMatchesTheDefaultsRead() {
        #expect(Steps.storedShortcutVersion(raw: 0, hasSetUpBefore: true) == 1)
        #expect(Steps.storedShortcutVersion(raw: 0, hasSetUpBefore: false) == 0)
        #expect(Steps.storedShortcutVersion(raw: 2, hasSetUpBefore: false) == 2)
        #expect(Steps.storedShortcutVersion(raw: 1, hasSetUpBefore: true) == 1)
    }

    /// First launch of a fresh install (nothing set up): stamped 2, so an
    /// iOS 26 "I'm Done" or an iOS 27 by-hand build on this build never
    /// shows the card. An install that set up before is left as it is.
    @Test func aFreshInstallIsStampedWithTheNewVersionAtLaunch() {
        let fresh = defaults()
        #expect(Steps.settleShortcutVersion(hasSetUpBefore: false, defaults: fresh))
        #expect(fresh.integer(forKey: Steps.shortcutVersionKey) == 2)
        #expect(!Steps.needsNewShortcut(route: .automation, hasReachedBefore: false, saysBuilt: true,
                                        storedVersion: Steps.storedShortcutVersion(hasSetUpBefore: true, defaults: fresh),
                                        dismissed: false))

        let old = defaults()
        #expect(!Steps.settleShortcutVersion(hasSetUpBefore: true, defaults: old))
        #expect(old.object(forKey: Steps.shortcutVersionKey) == nil)
        #expect(Steps.storedShortcutVersion(hasSetUpBefore: true, defaults: old) == 1)

        // Runs once: a later launch leaves the stamp alone.
        let done = defaults()
        Steps.markNewShortcut(defaults: done)
        #expect(!Steps.settleShortcutVersion(hasSetUpBefore: false, defaults: done))
    }

    /// What the views pass: the status, "I'm done", the raw stored version.
    @Test func theViewsReadFromTheStatus() {
        let at = Date(timeIntervalSince1970: 1_790_000_000)
        let tap = ApplePayStatus.tapLogged(date: at, merchant: "Seven Seeds", amount: 4.5, currency: "AUD")
        // iOS 27: any reach on an old install.
        #expect(Steps.needsNewShortcut(route: .shortcut, status: .shortcutReached(at), saysBuilt: false, rawVersion: 0))
        #expect(Steps.needsNewShortcut(route: .shortcut, status: tap, saysBuilt: true, rawVersion: 0))
        #expect(!Steps.needsNewShortcut(route: .shortcut, status: tap, saysBuilt: true, rawVersion: 2))
        #expect(!Steps.needsNewShortcut(route: .shortcut, status: .notConnected, saysBuilt: false, rawVersion: 0))
        // iOS 26: "I'm Done" with no tap yet; not once taps log.
        #expect(Steps.needsNewShortcut(route: .automation, status: .notConnected, saysBuilt: true, rawVersion: 0))
        #expect(!Steps.needsNewShortcut(route: .automation, status: tap, saysBuilt: true, rawVersion: 0))
        #expect(!Steps.needsNewShortcut(route: .automation, status: .tapNeedsCheck(date: at), saysBuilt: true, rawVersion: 0))
        #expect(!Steps.needsNewShortcut(route: .automation, status: .notConnected, saysBuilt: false, rawVersion: 0))
        #expect(!Steps.needsNewShortcut(route: .automation, status: .notConnected, saysBuilt: true, rawVersion: 2))
    }

    // MARK: - Copy

    @Test func theIOS27CopyIsWhatRajWrote() {
        let copy = Steps.newShortcutCopy(route: .shortcut)
        #expect(copy.title == "Get the new shortcut")
        #expect(copy.line == "This build reads your bank's alerts too, so Apple Pay in apps can log even when Wallet says nothing. It needs the new shortcut.")
        #expect(copy.steps.count == 3)
        #expect(copy.steps[0].contains("Delete"))
        #expect(copy.steps[0].contains("Log Apple Pay in Sortd"))
        #expect(copy.steps[1].contains("both automations"))
        #expect(copy.steps[2].contains("bank's app"))
        #expect(copy.steps[2].contains("purchase alerts"))
        #expect(copy.pageButton == "Get the Shortcut")
        #expect(copy.homeButton == "Show Me How")
        #expect(copy.doneButton == "I've Done It")
    }

    @Test func theIOS26CopyIsWhatRajWrote() {
        let copy = Steps.newShortcutCopy(route: .automation)
        #expect(copy.title == "What's new for iOS 26")
        #expect(copy.line == "If Sortd wasn't in the Shortcuts list when you made the automation, there is a way round now.")
        #expect(copy.steps == [
            "Open Sortd once, wait ten seconds, then restart your iPhone and try the automation again.",
            "Still missing? Build the shortcut first under My Shortcuts, then pick it in the Wallet automation.",
            "The full steps are on sortd.page/support under \u{201C}Sortd isn't in the list\u{201D}.",
        ])
        #expect(copy.pageButton == "Open the Steps")
        #expect(copy.homeButton == "Show Me How")
        #expect(copy.doneButton == "I've Done It")
        // "Open the Steps" opens the support page's fallback.
        #expect(Steps.missingFromListURL.absoluteString == "https://sortd.page/support#ios26-missing")
    }

    /// This is UI copy, so "Apple Pay" is fine; nothing else says "Apple".
    @Test func theCopySaysAppleOnlyAsApplePay() {
        for route in [Steps.Route.shortcut, .automation] {
            let copy = Steps.newShortcutCopy(route: route)
            for line in [copy.title, copy.line, copy.pageButton, copy.homeButton, copy.doneButton] + copy.steps {
                #expect(!line.isEmpty)
                #expect(!line.replacingOccurrences(of: "Apple Pay", with: "").contains("Apple"), "\(line)")
            }
        }
    }

    // MARK: - Analytics

    @Test func theActionsAreNamedPerRoute() {
        typealias A = Steps.NewShortcutAction
        #expect(A.shown.name(route: .shortcut) == "new_shortcut_shown")
        #expect(A.get.name(route: .shortcut) == "new_shortcut_get")
        #expect(A.done.name(route: .shortcut) == "new_shortcut_done")
        #expect(A.shown.name(route: .automation) == "ios26_whats_new_shown")
        #expect(A.get.name(route: .automation) == "ios26_whats_new_open")
        #expect(A.done.name(route: .automation) == "ios26_whats_new_done")
    }

    /// `shown` goes once per launch, whichever card appears first.
    @Test @MainActor func shownIsSentOncePerLaunch() {
        var sent = false
        #expect(Steps.claimShownOnce(&sent))
        #expect(!Steps.claimShownOnce(&sent))
    }
}

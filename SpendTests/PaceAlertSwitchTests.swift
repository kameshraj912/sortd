import Testing
import Foundation
import UserNotifications
@testable import Spend

/// Settings › Bills & Reminders: the Budget Pace Alert switch must not read ON
/// while iOS blocks notifications, because the alert can then never arrive.
/// The stored choice itself is not touched.
struct PaceAlertSwitchTests {
    @Test func onAndAllowedShowsOn() {
        #expect(Reminders.alertShownOn(stored: true, notificationsAllowed: true))
    }

    @Test func onButBlockedShowsOff() {
        #expect(!Reminders.alertShownOn(stored: true, notificationsAllowed: false))
    }

    @Test func offStaysOffWhateverIosSays() {
        #expect(!Reminders.alertShownOn(stored: false, notificationsAllowed: true))
        #expect(!Reminders.alertShownOn(stored: false, notificationsAllowed: false))
    }

    @Test(arguments: [(UNAuthorizationStatus.authorized, true), (.provisional, true), (.ephemeral, true),
                      (.denied, false), (.notDetermined, false)])
    func onlyAllowedStatesCount(status: UNAuthorizationStatus, allowed: Bool) {
        #expect(Reminders.allows(status) == allowed)
    }
}

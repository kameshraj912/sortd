import Testing
import Foundation
import UserNotifications
@testable import Spend

/// Settings › Bills & Reminders: the Budget Pace Alert switch must not read ON
/// while iOS blocks notifications, because the alert can then never arrive.
/// The stored choice itself is not touched.
struct PaceAlertSwitchTests {
    @Test func onAndAllowedShowsOn() {
        #expect(Reminders.paceAlertShownOn(stored: true, notificationsAllowed: true))
    }

    @Test func onButBlockedShowsOff() {
        #expect(!Reminders.paceAlertShownOn(stored: true, notificationsAllowed: false))
    }

    @Test func offStaysOffWhateverIosSays() {
        #expect(!Reminders.paceAlertShownOn(stored: false, notificationsAllowed: true))
        #expect(!Reminders.paceAlertShownOn(stored: false, notificationsAllowed: false))
    }

    @Test(arguments: [(UNAuthorizationStatus.authorized, true), (.provisional, true), (.ephemeral, true),
                      (.denied, false), (.notDetermined, false)])
    func onlyAllowedStatesCount(status: UNAuthorizationStatus, allowed: Bool) {
        #expect(Reminders.allows(status) == allowed)
    }
}

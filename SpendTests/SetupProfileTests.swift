import Testing
import Foundation
@testable import Spend

/// Setup answers decide which steps show. Nothing here leads with, or waits
/// for, Pro any more (overhaul sub-spec 1: the whole app is free).
///
/// `SetupProfile.proOrder` is deleted along with `ProStore`; these tests do
/// not reference it or `ProStore.Feature`.
@MainActor
struct SetupProfileTests {

    @Test func goalsSurviveBeingSaved() {
        let goals: Set<SetupProfile.Goal> = [.spendLess, .bills]
        #expect(SetupProfile.goals(SetupProfile.raw(goals)) == goals)
        #expect(SetupProfile.goals("") == [])
        #expect(SetupProfile.goals("nonsense,bills") == [.bills])
    }

    @Test func quietModeSchedulesNothing() {
        #expect(SetupProfile.CheckIn.needed.time == nil)
        #expect(SetupProfile.CheckIn.sunday.time?.weekday == 1)
        #expect(SetupProfile.CheckIn.morning.time?.hour == 8)
    }

    /// Someone asked for bill reminders during setup. In the free app there
    /// is no Pro gate left to wait for: a pending request turns reminders
    /// on the next time `applyPendingBillReminders` runs, full stop.
    @Test func pendingBillReminderTurnsRemindersOnWithNoProCondition() {
        let d = UserDefaults(suiteName: "SetupProfileTests-\(UUID().uuidString)")!
        d.set(true, forKey: SetupProfile.billsKey)
        d.set(false, forKey: Reminders.enabledKey)

        SetupProfile.applyPendingBillReminders(defaults: d)

        #expect(d.bool(forKey: Reminders.enabledKey))
        #expect(!d.bool(forKey: SetupProfile.billsKey))
    }

    /// No pending request: nothing changes.
    @Test func noPendingBillReminderChangesNothing() {
        let d = UserDefaults(suiteName: "SetupProfileTests-\(UUID().uuidString)")!
        d.set(false, forKey: SetupProfile.billsKey)
        d.set(false, forKey: Reminders.enabledKey)

        SetupProfile.applyPendingBillReminders(defaults: d)

        #expect(!d.bool(forKey: Reminders.enabledKey))
    }
}

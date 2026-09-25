import Testing
@testable import Spend

/// The spec (`docs/specs/2026-09-25-free-app-overhaul-1-free.md`, "Test
/// plan") asks the builder to extract a pure
/// `Reminders.shouldSchedule(enabled: Bool) -> Bool` that takes only the
/// on/off setting -- no Pro, no other input. It does not exist yet, kept in
/// its own file so a missing symbol here doesn't stop the rest of
/// `FreeAppTests.swift` from compiling and running.
@MainActor
struct RemindersShouldScheduleTests {
    @Test func trueWhenEnabled() {
        #expect(Reminders.shouldSchedule(enabled: true))
    }

    @Test func falseWhenNotEnabled() {
        #expect(!Reminders.shouldSchedule(enabled: false))
    }
}

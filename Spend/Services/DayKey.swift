import Foundation

/// Dates that are sent to a server, used as keys, or read off a statement
/// are always Gregorian.
///
/// `Calendar.current` follows the phone's calendar setting. On a Thai phone
/// (Buddhist calendar, the default there) 2026 is year 2569; on a Japanese
/// calendar it is Reiwa 8. Frankfurter's dates and the saved rate keys,
/// export file names and the years printed on bank statements are all
/// Gregorian, so building them with `Calendar.current` asked the server for
/// "2569-09-17" and read a statement's 2026 as 1483 CE. Screens keep the
/// phone's own calendar; only these use this one.
nonisolated enum DayKey {
    /// Gregorian, in the phone's time zone.
    static var calendar: Calendar { gregorian(like: .current) }

    /// Gregorian whatever `calendar` is, keeping its time zone, so the day
    /// still turns over at the phone's own midnight.
    static func gregorian(like calendar: Calendar) -> Calendar {
        guard calendar.identifier != .gregorian else { return calendar }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }

    /// "2026-09-18": the day `date` falls on, in `calendar`'s time zone.
    static func string(_ date: Date, calendar: Calendar = DayKey.calendar) -> String {
        let c = gregorian(like: calendar).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

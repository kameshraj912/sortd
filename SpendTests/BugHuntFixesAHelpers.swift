import Testing
import Foundation
import SwiftData
@testable import Spend

/// Shared helpers for the `BugHuntFixesA*Tests` suites: regression tests for
/// the 3 Oct 2026 bug hunt findings fixed on branch `fix-hunt-a`. Each test
/// failed before its fix (see docs/BugHunt-2026-10-03-fixes-a.md).
enum HuntA {
    @MainActor static func store() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    /// A Gregorian date and time in this time zone.
    static func date(_ ymd: String, _ hm: String = "12:00") -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = .current
        return f.date(from: "\(ymd) \(hm)")!
    }

    static func money(_ s: String) -> Decimal { Decimal(string: s)! }

    static func calendar(_ id: Calendar.Identifier, _ zone: TimeZone = .current) -> Calendar {
        var c = Calendar(identifier: id)
        c.timeZone = zone
        return c
    }

    /// Year, month and day in the Gregorian calendar, in this time zone.
    static func ymd(_ d: Date?) -> String? {
        guard let d else { return nil }
        let c = calendar(.gregorian).dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

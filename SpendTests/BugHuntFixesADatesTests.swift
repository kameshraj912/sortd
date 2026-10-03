import Testing
import Foundation
import SwiftData
@testable import Spend

/// Bug hunt 3 Oct 2026, fixed on `fix-hunt-a`: Day keys and statement dates are Gregorian on any phone calendar (M1, S1).
/// Each test failed before its fix. Helpers: `HuntA`.
@MainActor
struct BugHuntFixesADatesTests {

    private func store() throws -> ModelContext { try HuntA.store() }
    private func date(_ ymd: String, _ hm: String = "12:00") -> Date { HuntA.date(ymd, hm) }
    private func money(_ s: String) -> Decimal { HuntA.money(s) }
    private func calendar(_ id: Calendar.Identifier, _ zone: TimeZone = .current) -> Calendar { HuntA.calendar(id, zone) }
    private func ymd(_ d: Date?) -> String? { HuntA.ymd(d) }

    // MARK: M1. FX day keys

    /// The Frankfurter URL and the FXRate keys are Gregorian. A Thai
    /// (Buddhist) or Japanese phone calendar must not change them, or no
    /// foreign purchase is ever converted.
    @Test func fxDayKeysAreGregorianOnAThaiOrJapanesePhone() {
        let melbourne = TimeZone(identifier: "Australia/Melbourne")!
        let at = Date(timeIntervalSince1970: 1_790_000_000)   // 22 Sep 2026, 00:13 in Melbourne
        #expect(FXService.dayString(at, calendar: calendar(.buddhist, melbourne)) == "2026-09-22")
        #expect(FXService.dayString(at, calendar: calendar(.japanese, melbourne)) == "2026-09-22")
        #expect(FXService.dayString(at, calendar: calendar(.gregorian, melbourne)) == "2026-09-22")
        // The day is the phone's own day: Singapore is still on the 21st.
        #expect(FXService.dayString(at, calendar: calendar(.buddhist, TimeZone(identifier: "Asia/Singapore")!)) == "2026-09-21")
        // The default is Gregorian in the phone's time zone.
        #expect(FXService.dayString(at) == ymd(at))
    }

    // MARK: S1. Statement dates on a Thai or Japanese phone

    @Test func statementDatesAreGregorianOnAThaiOrJapanesePhone() {
        for id in [Calendar.Identifier.buddhist, .japanese] {
            let rows = StatementImport.rows(fromCSV: "Date,Description,Amount\n01/09/2026,WOOLWORTHS 3342,-58.30",
                                            calendar: calendar(id))
            #expect(rows.count == 1)
            #expect(ymd(rows.first?.date) == "2026-09-01", "\(id)")

            // A line with no year takes this year (Gregorian), and is not lost.
            let text = StatementImport.parse(text: "28 Sep  SEVEN SEEDS COFFEE  5.50",
                                             today: date("2026-10-03"), calendar: calendar(id))
            #expect(text.rows.count == 1, "\(id)")
            #expect(ymd(text.rows.first?.date) == "2026-09-28", "\(id)")
            #expect(ymd(StatementImport.parseDate("Sep 28", order: .dayFirst, today: date("2026-10-03"),
                                                  calendar: calendar(id))) == "2026-09-28")
        }
        // The default calendar is Gregorian too.
        #expect(ymd(StatementImport.rows(fromCSV: "Date,Description,Amount\n01/09/2026,WOOLWORTHS,-58.30").first?.date) == "2026-09-01")
    }
}

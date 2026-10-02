import Testing
import Foundation
import Sentry
@testable import Spend

/// `ErrorLog`: the ring buffer of the last 20 failures, and what a non-fatal
/// sends to Sentry (the place and the error type, nothing else).
struct ErrorLogTests {
    private struct Boom: LocalizedError {
        var errorDescription: String? { "Disk full while saving Coles 12.50" }
    }

    private func freshDefaults() -> UserDefaults {
        let name = "ErrorLogTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func entry(_ n: Int) -> ErrorLog.Entry {
        ErrorLog.Entry(date: Date(timeIntervalSince1970: Double(n)), place: "p\(n)", type: "T", message: "m")
    }

    @Test func trimmedKeepsShortTextAndCutsLongTextToTheLimit() {
        #expect(ErrorLog.trimmed("short") == "short")
        let long = String(repeating: "a", count: 300)
        let cut = ErrorLog.trimmed(long)
        #expect(cut.count == 120)
        #expect(cut.hasSuffix("…"))
        #expect(ErrorLog.trimmed(String(repeating: "b", count: 120)).count == 120)
    }

    @Test func trimmedFlattensNewlines() {
        #expect(ErrorLog.trimmed("one\ntwo\r\nthree") == "one two three")
    }

    @Test func entryHoldsTheTypeNameAndATrimmedDescription() {
        let e = ErrorLog.entry(for: Boom(), where: "TransactionDetail.save", at: .distantPast)
        #expect(e.type == "Boom")
        #expect(e.place == "TransactionDetail.save")
        #expect(e.message == "Disk full while saving Coles 12.50")
        let longErr = NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: String(repeating: "z", count: 500)])
        #expect(ErrorLog.entry(for: longErr, where: "w", at: .now).message.count == 120)
    }

    @Test func addingPutsTheNewestFirst() {
        let list = ErrorLog.adding(entry(2), to: [entry(1)])
        #expect(list.map(\.place) == ["p2", "p1"])
    }

    @Test func addingCapsTheListAtTwenty() {
        var list: [ErrorLog.Entry] = []
        for n in 1...30 { list = ErrorLog.adding(entry(n), to: list) }
        #expect(list.count == 20)
        #expect(list.first?.place == "p30")
        #expect(list.last?.place == "p11")
    }

    @Test func reportStoresAndRecentReadsBackNewestFirst() {
        let d = freshDefaults()
        ErrorLog.report(Boom(), where: "first", defaults: d, now: Date(timeIntervalSince1970: 1))
        ErrorLog.report(Boom(), where: "second", defaults: d, now: Date(timeIntervalSince1970: 2))
        #expect(ErrorLog.recent(defaults: d).map(\.place) == ["second", "first"])
        ErrorLog.clear(defaults: d)
        #expect(ErrorLog.recent(defaults: d).isEmpty)
    }

    @Test func reportNeverGrowsPastTwenty() {
        let d = freshDefaults()
        for n in 1...25 { ErrorLog.report(Boom(), where: "w\(n)", defaults: d, now: Date(timeIntervalSince1970: Double(n))) }
        let list = ErrorLog.recent(defaults: d)
        #expect(list.count == 20)
        #expect(list.first?.place == "w25")
    }

    @Test func nonFatalCarriesOnlyThePlaceAndTheErrorTypeAfterScrub() {
        let event = CrashReporting.nonFatalEvent(where: "Backup.save", errorType: "CocoaError")
        let scrubbed = CrashReporting.scrub(event, userId: nil)
        #expect(scrubbed.exceptions?.first?.type == "Backup.save: CocoaError")
        #expect(scrubbed.exceptions?.first?.value == nil || scrubbed.exceptions?.first?.value == "")
        #expect(scrubbed.message == nil)
        #expect(scrubbed.tags == nil)
        #expect(scrubbed.extra == nil)
        #expect(scrubbed.breadcrumbs == nil)
    }
}

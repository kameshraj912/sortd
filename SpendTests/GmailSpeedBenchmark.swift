import Testing
import Foundation
import SwiftData
@testable import Spend

/// Before/after timings against the pretend Gmail (MockGmail, no network,
/// no Google account) with a fixed delay per request. Off by default, so CI
/// skips it: it is slow and prints timings rather than checking anything.
/// `TEST_RUNNER_SPEND_BENCH=1 scripts/test.sh --only GmailSpeedBenchmark`
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SPEND_BENCH"] == "1"))
struct GmailSpeedBenchmark {

    static let emails = 300
    static let latency = 0.15

    private func freshContext() throws -> ModelContext {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        // On disk, like the phone: each save is a real SQLite write.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bench-\(UUID().uuidString).store")
        return ModelContext(try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)]))
    }

    private func report(_ label: String, _ values: [(String, Double)]) {
        let text = values.map { "\($0.0)=\(String(format: "%.0f", $0.1))ms" }.joined(separator: " ")
        print("BENCH \(label) n=\(Self.emails) latency=\(Int(Self.latency * 1000))ms \(text)")
    }

    /// The sync as it was: 100 ids a page; oldest first; 20 at a time in
    /// lock-step groups of 4; read on the main actor; one save per purchase.
    @Test func before() async throws {
        let context = try freshContext()
        let gmail = MockGmail()
        gmail.addPurchases(Self.emails)
        gmail.latency = Self.latency
        let api = gmail.api
        let start = ContinuousClock.now

        var ids: [String] = []
        var page: String?
        repeat {
            var url = URLComponents(string: api.base)!
            url.queryItems = [.init(name: "q", value: "x"), .init(name: "maxResults", value: "100")]
            if let page { url.queryItems?.append(.init(name: "pageToken", value: page)) }
            struct R: Decodable { struct Ref: Decodable { let id: String }; let messages: [Ref]?; let nextPageToken: String? }
            let r: R = try await api.get(url.url!)
            ids += (r.messages ?? []).map(\.id)
            page = r.nextPageToken
        } while page != nil && ids.count < 1000
        let listed = Perf.ms(since: start)

        let fresh = Array(ids.reversed())
        var firstShown: Double?
        var readMs = 0.0, saveMs = 0.0
        for s in stride(from: 0, to: fresh.count, by: 20) {
            let batch = Array(fresh[s..<min(s + 20, fresh.count)])
            var messages: [EmailParsers.Message] = []
            for chunk in stride(from: 0, to: batch.count, by: 4).map({ Array(batch[$0..<min($0 + 4, batch.count)]) }) {
                try await withThrowingTaskGroup(of: EmailParsers.Message?.self) { group in
                    for id in chunk { group.addTask { try await api.message(id) } }
                    for try await m in group { if let m { messages.append(m) } }
                }
            }
            let t = ContinuousClock.now
            var records: [EmailRecord] = []
            for m in messages { records += await GmailSync.read(m) }
            readMs += Perf.ms(since: t)
            let t2 = ContinuousClock.now
            // One save per purchase, as TransactionLogger.log used to do.
            for r in records {
                let p = IncomingPurchase(date: ISO8601DateFormatter.fractional.date(from: r.date) ?? .now, merchant: r.merchant,
                                         amount: Decimal(string: r.amount) ?? 0, currency: r.currency, card: .other, source: .email)
                _ = try TransactionLogger.log(p, in: context)
                context.insert(ImportedRecord(id: r.id, account: "a"))
            }
            try context.save()
            saveMs += Perf.ms(since: t2)
            if firstShown == nil { firstShown = Perf.ms(since: start) }
        }
        report("before", [("list", listed), ("firstPurchaseOnScreen", firstShown ?? 0), ("total", Perf.ms(since: start)),
                          ("readOnMain", readMs), ("saveOnMain", saveMs)])
    }

    @Test func after() async throws {
        let context = try freshContext()
        let gmail = MockGmail()
        gmail.addPurchases(Self.emails)
        gmail.latency = Self.latency
        let api = gmail.api
        let start = ContinuousClock.now
        let (ids, _) = try await api.listMessages(query: "x")
        let listed = Perf.ms(since: start)
        var firstShown: Double?
        let fresh = GmailSync.unread(ids, in: context)
        _ = try await GmailSync.importMessages(fresh, api: api, account: "a", aiAvailable: false, in: context) { _, _, added in
            if added > 0, firstShown == nil { firstShown = Perf.ms(since: start) }
        }
        report("after", [("list", listed), ("firstPurchaseOnScreen", firstShown ?? 0), ("total", Perf.ms(since: start))])
    }

    /// Saving 300 purchases: one save each (before) vs a few batched saves (after).
    @Test func savingOnly() throws {
        let records = (0..<Self.emails).map { i in
            EmailRecord(id: "s\(i)-0", kind: "purchase", merchant: "Shop \(i)", rawMerchant: "SHOP \(i)", platform: nil,
                        amount: String(format: "%.2f", 10 + Double(i)), currency: "AUD", card: "other",
                        date: ISO8601DateFormatter.fractional.string(from: Date.now.addingTimeInterval(-Double(i) * 3600)),
                        note: nil, subscription: nil)
        }
        let a = try freshContext()
        var t = ContinuousClock.now
        for r in records {
            let p = IncomingPurchase(date: ISO8601DateFormatter.fractional.date(from: r.date) ?? .now, merchant: r.merchant,
                                     amount: Decimal(string: r.amount) ?? 0, currency: r.currency, card: .other, source: .email)
            _ = try TransactionLogger.log(p, in: a)
        }
        let before = Perf.ms(since: t)
        let b = try freshContext()
        t = ContinuousClock.now
        for s in stride(from: 0, to: records.count, by: 10) {
            try EmailSync.importRecords(Array(records[s..<min(s + 10, records.count)]), in: b)
        }
        let after = Perf.ms(since: t)
        report("saving", [("before", before), ("after", after)])
    }

    /// A 300-line bank statement.
    @Test func statementImport() throws {
        let rows = (0..<Self.emails).map { i in
            StatementImport.Row(date: Date.now.addingTimeInterval(-Double(i) * 7200), detail: "SHOP \(i)",
                                amount: Decimal(10 + i), currency: "AUD", kind: .spend, raw: "")
        }
        // Before: one save per row.
        let a = try freshContext()
        var t = ContinuousClock.now
        var touched: Set<UUID> = []
        for row in rows {
            let p = IncomingPurchase(date: row.date, merchant: row.detail, amount: row.amount,
                                     currency: "AUD", card: .other, source: .csv)
            if let o = try? TransactionLogger.log(p, in: a, excluding: touched) { touched.insert(o.transaction.id) }
        }
        let before = Perf.ms(since: t)
        let c = try freshContext()
        t = ContinuousClock.now
        _ = StatementImport.save(rows, card: .other, in: c)
        report("statement", [("before", before), ("after", Perf.ms(since: t))])
    }
}

extension ISO8601DateFormatter {
    static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

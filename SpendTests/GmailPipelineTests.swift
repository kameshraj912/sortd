import Testing
import Foundation
import SwiftData
@testable import Spend

// MARK: - A pretend Gmail

/// A fake Gmail REST server behind URLProtocol. Each test gets its own
/// server, found by the bearer token, so tests running side by side don't
/// share state.
final class MockGmail: @unchecked Sendable {
    struct Mail { let id: String; let from: String; let subject: String; let body: String; let date: Date }

    private let lock = NSLock()
    /// Newest first, like Gmail.
    var mails: [Mail] = []
    /// Seconds each request takes.
    var latency: Double = 0
    /// Message ids that answer 404 (deleted after the list).
    var missing: Set<String> = []
    /// Message ids that answer 429 this many times before working.
    var rateLimited: [String: Int] = [:]

    private(set) var listCalls = 0
    private(set) var messageCalls = 0
    private(set) var inFlight = 0
    private(set) var maxInFlight = 0
    private(set) var pageSizes: [Int] = []

    let token = UUID().uuidString
    static let lockAll = NSLock()
    nonisolated(unsafe) static var servers: [String: MockGmail] = [:]

    init() {
        Self.lockAll.withLock { Self.servers[token] = self }
    }

    deinit { Self.lockAll.withLock { _ = Self.servers.removeValue(forKey: token) } }

    var api: GmailAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockGmailProtocol.self]
        config.httpMaximumConnectionsPerHost = 32
        var api = GmailAPI(token: token, session: URLSession(configuration: config))
        api.sleep = { _ in }
        return api
    }

    func started() { lock.withLock { inFlight += 1; maxInFlight = max(maxInFlight, inFlight) } }
    func finished() { lock.withLock { inFlight -= 1 } }

    /// (status, body)
    func answer(_ url: URL) -> (Int, Data) {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let q = Dictionary((comps.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        let last = url.lastPathComponent
        if last == "messages" {
            let size = Int(q["maxResults"] ?? "100") ?? 100
            let start = Int(q["pageToken"] ?? "0") ?? 0
            lock.withLock { listCalls += 1; pageSizes.append(size) }
            let page = Array(mails.dropFirst(start).prefix(size))
            var json: [String: Any] = ["messages": page.map { ["id": $0.id] }]
            if start + size < mails.count { json["nextPageToken"] = String(start + size) }
            return (200, try! JSONSerialization.data(withJSONObject: json))
        }
        let id = last
        lock.withLock { messageCalls += 1 }
        if missing.contains(id) { return (404, Data(#"{"error":{"code":404}}"#.utf8)) }
        let limited: Bool = lock.withLock {
            if let n = rateLimited[id], n > 0 { rateLimited[id] = n - 1; return true }
            return false
        }
        if limited { return (429, Data(#"{"error":{"code":429,"message":"rateLimitExceeded"}}"#.utf8)) }
        guard let m = mails.first(where: { $0.id == id }) else { return (404, Data()) }
        let body = Data(m.body.utf8).base64URL
        let json: [String: Any] = [
            "id": m.id,
            "internalDate": String(Int(m.date.timeIntervalSince1970 * 1000)),
            "payload": [
                "mimeType": "text/plain",
                "headers": [["name": "From", "value": m.from], ["name": "Subject", "value": m.subject]],
                "body": ["data": body],
            ] as [String: Any],
        ]
        return (200, try! JSONSerialization.data(withJSONObject: json))
    }

    /// NAB-style alerts: known sender, exact rules, no on-device model needed.
    func addPurchases(_ n: Int, newest: Date = .now, spacing: TimeInterval = 3600, prefix: String = "p") {
        for i in 0..<n {
            let amount = String(format: "%.2f", 10 + Double(i))
            mails.append(Mail(id: "\(prefix)\(String(format: "%04d", i))", from: "alerts@nab.com.au", subject: "Transaction alert",
                              body: "A purchase of $\(amount) was made at SHOP \(i) on your card ending 1234.",
                              date: newest.addingTimeInterval(-Double(i) * spacing)))
        }
    }
}

final class MockGmailProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let token = (request.value(forHTTPHeaderField: "Authorization") ?? "").replacingOccurrences(of: "Bearer ", with: "")
        guard let server = MockGmail.lockAll.withLock({ MockGmail.servers[token] }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        server.started()
        let respond = { [self] in
            let (code, data) = server.answer(url)
            server.finished()
            let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
        if server.latency > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + server.latency, execute: respond)
        } else {
            respond()
        }
    }

    override func stopLoading() {}
}

// MARK: - Tests

@MainActor
@Suite(.serialized)
struct GmailPipelineTests {
    let context: ModelContext

    init() throws {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    var all: [Transaction] { (try? context.fetch(FetchDescriptor<Transaction>())) ?? [] }

    @Test func listingUsesBigPagesAndStopsAtTheCap() async throws {
        let gmail = MockGmail()
        gmail.addPurchases(1200)
        let (ids, truncated) = try await gmail.api.listMessages(query: "x")
        #expect(ids.count == 1000)
        #expect(truncated)
        // 500 a page: two round trips for the 1,000 cap (was ten at 100 a page).
        #expect(gmail.listCalls == 2)
        #expect(gmail.pageSizes.allSatisfy { $0 == 500 })
    }

    @Test func listingReportsTheRunningCount() async throws {
        let gmail = MockGmail()
        gmail.addPurchases(700)
        let counts = Counter()
        _ = try await gmail.api.listMessages(query: "x") { await counts.add($0) }
        #expect(await counts.values == [500, 700])
    }

    @Test func downloadsRunSideBySideButNeverMoreThanTheLimit() async throws {
        let gmail = MockGmail()
        gmail.addPurchases(30)
        gmail.latency = 0.05
        var api = gmail.api
        api.concurrency = 6
        let ids = gmail.mails.map(\.id)
        let s = try await GmailSync.importMessages(ids, api: api, account: "a@b.com", aiAvailable: false, in: context)
        #expect(s.added == 30)
        #expect(s.checked == 30)
        #expect(gmail.maxInFlight <= 6)
        #expect(gmail.maxInFlight >= 4)
        #expect(gmail.messageCalls == 30)
    }

    @Test func tooFastWaitsAndTriesAgain() async throws {
        let gmail = MockGmail()
        gmail.addPurchases(3)
        gmail.rateLimited = ["p0001": 2]
        let waits = Counter()
        var api = gmail.api
        api.sleep = { await waits.add(Int($0 * 1000)) }
        let s = try await GmailSync.importMessages(gmail.mails.map(\.id), api: api, account: "a@b.com", aiAvailable: false, in: context)
        #expect(s.added == 3)
        let w = await waits.values
        #expect(w.count == 2)
        // Backs off: the second wait is longer than the first.
        #expect(w[1] > w[0])
    }

    @Test func stillTooFastAfterEveryRetryStopsButKeepsWhatWasRead() async throws {
        let gmail = MockGmail()
        gmail.addPurchases(12)
        gmail.rateLimited = ["p0011": 99]
        var api = gmail.api
        api.concurrency = 1
        await #expect(throws: GmailError.self) {
            try await GmailSync.importMessages(gmail.mails.map(\.id), api: api, account: "a@b.com", aiAvailable: false, in: context)
        }
        // The eleven read before the stubborn one are saved.
        #expect(all.count == 11)
    }

    @Test func aDeletedEmailIsSkippedNotAnError() async throws {
        let gmail = MockGmail()
        gmail.addPurchases(5)
        gmail.missing = ["p0002"]
        let s = try await GmailSync.importMessages(gmail.mails.map(\.id), api: gmail.api, account: "a@b.com", aiAvailable: false, in: context)
        #expect(s.added == 4)
    }

    @Test func purchasesAppearNewestFirstAndInSteps() async throws {
        let gmail = MockGmail()
        gmail.addPurchases(35)
        var api = gmail.api
        api.concurrency = 1   // exact order, for the check below
        var saves = 0
        let token = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context, queue: nil) { _ in
            MainActor.assumeIsolated { saves += 1 }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        var firstSeen: [Date] = []
        let newest = gmail.mails[0].date
        let s = try await GmailSync.importMessages(gmail.mails.map(\.id), api: api, account: "a@b.com", aiAvailable: false,
                                                   in: context, flushEvery: 10, flushInterval: 60) { _, _, added in
            if added > 0, firstSeen.isEmpty { firstSeen = self.all.map(\.date) }
        }
        #expect(s.added == 35)
        // The first purchases on screen are the newest ten.
        #expect(firstSeen.count == 10)
        // (Gmail keeps milliseconds, so compare to the second.)
        let tenth = gmail.mails[9].date
        #expect(abs((firstSeen.max() ?? .distantPast).timeIntervalSince(newest)) < 1)
        #expect((firstSeen.min() ?? .distantPast) > tenth.addingTimeInterval(-1))
        // Saved in steps (35 / 10 → 4), not once per purchase and not all at the end.
        #expect(saves >= 4 && saves <= 6)
    }

    @Test func aNewerRefundStillFindsItsOlderPurchase() async throws {
        let gmail = MockGmail()
        let now = Date.now
        // Newest first: the refund arrives before the purchase it cancels.
        gmail.mails = [
            .init(id: "r1", from: "alerts@nab.com.au", subject: "Refund",
                  body: "A refund of $38.00 from KMART has been credited to your card ending 1234.", date: now),
            .init(id: "k1", from: "alerts@nab.com.au", subject: "Transaction alert",
                  body: "A purchase of $38.00 was made at KMART on your card ending 1234.", date: now.addingTimeInterval(-86400)),
        ]
        let s = try await GmailSync.importMessages(["r1", "k1"], api: gmail.api, account: "a@b.com", aiAvailable: false, in: context)
        #expect(s.added == 1)
        #expect(s.refunds == 1)
        #expect(all.first?.refunded == true)
    }

    @Test func emailsAlreadyReadAreNotDownloadedAgain() async throws {
        let gmail = MockGmail()
        gmail.addPurchases(8)
        let ids = gmail.mails.map(\.id)
        _ = try await GmailSync.importMessages(Array(ids.prefix(5)), api: gmail.api, account: "a@b.com", aiAvailable: false, in: context)
        let fresh = GmailSync.unread(ids, in: context)
        #expect(fresh == Array(ids.suffix(3)))
        _ = try await GmailSync.importMessages(fresh, api: gmail.api, account: "a@b.com", aiAvailable: false, in: context)
        #expect(gmail.messageCalls == 8)
        #expect(all.count == 8)
    }

    @Test func disconnectingMidSyncStopsWithoutWriting() async throws {
        let gmail = MockGmail()
        gmail.addPurchases(20)
        await #expect(throws: CancellationError.self) {
            try await GmailSync.importMessages(gmail.mails.map(\.id), api: gmail.api, account: "a@b.com", aiAvailable: false,
                                               in: context, stillConnected: { false })
        }
        #expect(all.isEmpty)
    }

    @Test func notAReceiptIsRememberedSoItIsSkippedNextTime() async throws {
        let gmail = MockGmail()
        gmail.mails = [.init(id: "n1", from: "alerts@nab.com.au", subject: "Earn more on your savings",
                             body: "Rates up to 4.50% p.a.", date: .now)]
        _ = try await GmailSync.importMessages(["n1"], api: gmail.api, account: "a@b.com", aiAvailable: false, in: context)
        #expect(GmailSync.unread(["n1"], in: context).isEmpty)
    }

    // MARK: One sync at a time

    /// Counts runs of a pretend sync that takes a moment.
    @MainActor final class Runs {
        var count = 0
        func work() async -> EmailSync.Summary {
            count += 1
            try? await Task.sleep(for: .milliseconds(50))
            var s = EmailSync.Summary()
            s.added = count
            return s
        }
    }

    @Test func twoSyncsAtOnceShareOneRun() async {
        let runs = Runs()
        // Main-actor tasks start in the order they were made.
        let a = Task { await GmailSync.exclusive(force: false) { await runs.work() } }
        let b = Task { await GmailSync.exclusive(force: false) { await runs.work() } }
        let first = await a.value, second = await b.value
        #expect(runs.count == 1)
        #expect(first == second)
    }

    @Test func aForcedSyncRunsAgainAfterAnAutomaticOne() async {
        let runs = Runs()
        let automatic = Task { await GmailSync.exclusive(force: false) { await runs.work() } }
        let forced = Task { await GmailSync.exclusive(force: true) { await runs.work() } }
        _ = await automatic.value
        _ = await forced.value
        // The automatic one may skip accounts synced a moment ago; Sync Now must not.
        #expect(runs.count == 2)
        // Nothing is left marked as running.
        _ = await GmailSync.exclusive(force: false) { await runs.work() }
        #expect(runs.count == 3)
    }

    // MARK: Failures in plain words

    @Test func failuresAreOneShortSentenceWithTheRightFix() {
        let offline = SyncFailure.from(URLError(.notConnectedToInternet))
        #expect(offline.kind == .offline)
        #expect(offline.retryTitle == "Try Again")
        let expired = SyncFailure.from(GmailError(code: 401, body: ""))
        #expect(expired.kind == .expired)
        #expect(expired.retryTitle == "Connect Again")
        #expect(SyncFailure.from(GmailError(code: 403, body: "insufficientPermissions")).kind == .accessDenied)
        #expect(SyncFailure.from(GmailError(code: 429, body: "")).kind == .slowDown)
        #expect(SyncFailure.from(GmailError(code: 500, body: "")).kind == .google)
        #expect(SyncFailure.from(GoogleAuth.AuthError.missingGmailAccess).needsSignIn)
    }

    @Test func statusWordsFollowTheSteps() {
        let s = SyncStatus()
        let job = s.begin(quiet: false)
        s.update(.signingIn, job: job)
        #expect(s.title == "Opening Google sign-in…")
        s.update(.connecting, job: job)
        #expect(s.title == "Connecting your Gmail…")
        s.update(.searching(found: 12), job: job)
        #expect(s.title == "Looking for receipts… (found 12)")
        s.update(.adding(done: 3, total: 12, added: 2), job: job)
        #expect(s.fraction == 0.25)
        s.update(.finished(added: 1), job: job)
        #expect(s.title == "Done. 1 purchase added.")
        #expect(s.showsOnHome)
    }

    @Test func aNewerJobOwnsTheStatusLine() {
        let s = SyncStatus()
        let background = s.begin(quiet: true)
        s.update(.searching(found: 0), job: background)
        #expect(!s.showsOnHome)
        let person = s.begin(quiet: false)
        s.update(.signingIn, job: person)
        s.update(.finished(added: 0), job: background)   // ignored
        #expect(s.phase == .signingIn)
    }

    @Test func aQuietSyncOnlyShowsWhenThereIsSomethingToSay() {
        let s = SyncStatus()
        let job = s.begin(quiet: true)
        s.update(.finished(added: 0), job: job)
        #expect(!s.showsOnHome)
        s.update(.adding(done: 1, total: 4, added: 1), job: job)
        #expect(s.showsOnHome)
        s.update(.failed(SyncFailure(kind: .offline, message: "")), job: job)
        #expect(!s.showsOnHome)
        s.update(.failed(SyncFailure(kind: .expired, message: "")), job: job)
        #expect(s.showsOnHome)
    }
}

/// Collects values from @Sendable closures.
actor Counter {
    private(set) var values: [Int] = []
    func add(_ v: Int) { values.append(v) }
}

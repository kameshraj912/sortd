import Foundation
import SwiftData

/// A Gmail account connected with "Connect with Google". Kept in
/// UserDefaults (email and sync status only); the token is in the Keychain.
struct GmailAccount: Codable, Identifiable, Hashable {
    var email: String
    var connectedAt: Date = .now
    var lastSync: Date?
    var lastResult: String?
    /// Catching up past Gmail's 1,000-per-sync cap: only look at emails older
    /// than this next time. Nil when caught up.
    var backfillBefore: Date?
    /// When the catch-up began. Once it's done, `lastSync` becomes this, so
    /// emails that arrived during the catch-up are still read.
    var backfillStartedAt: Date?
    var id: String { email }
}

/// A Gmail API error in plain words.
struct GmailError: LocalizedError {
    let code: Int
    let body: String
    var errorDescription: String? {
        if code == 401 || body.contains("invalid_grant") { return "Google access has ended. Disconnect and connect this Gmail again." }
        if body.contains("insufficient") { return "Sortd doesn't have permission to read receipts. Disconnect, connect again and tick the Gmail box." }
        if body.contains("accessNotConfigured") || body.contains("SERVICE_DISABLED") { return "Gmail access isn't switched on for Sortd yet. Try again in a few minutes." }
        if body.contains("rateLimit") || body.contains("Quota exceeded") || code == 429 {
            return "Gmail asked Sortd to slow down. What's been read is saved; the rest comes on the next sync."
        }
        return "Gmail answered with an error (\(code))."
    }
}

/// Reads receipt emails straight from Gmail on the phone, parses them with
/// `EmailParsers`, and imports them like any other email purchase. Nothing
/// is sent anywhere but Google; nothing is stored off the device.
enum GmailSync {
    private static let accountsKey = "gmailAccounts"
    /// How far back the first sync looks.
    static let firstSyncDays = 120

    /// Goes up each time Delete All runs. A sync that started before then
    /// stops without saving anything, even if the same Gmail has been
    /// connected again while it was still downloading.
    @MainActor private(set) static var resetGeneration = 0

    /// Called by Delete All, before it wipes the store.
    @MainActor static func cancelRunningSyncs() { resetGeneration += 1 }

    static var accounts: [GmailAccount] {
        get {
            guard let data = UserDefaults.standard.data(forKey: accountsKey) else { return [] }
            return (try? JSONDecoder().decode([GmailAccount].self, from: data)) ?? []
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: accountsKey) }
    }

    /// Signs in and runs the first sync of that account, reporting each
    /// step to `SyncStatus.gmail`.
    @MainActor
    static func connect(in context: ModelContext) async throws -> EmailSync.Summary {
        let status = SyncStatus.gmail
        let job = status.begin(quiet: false)
        status.update(.signingIn, job: job)
        let total = Perf.begin("gmail.connect")
        // Closing Google's sheet makes the app active again, which starts the
        // app's own sync. It must not race this one for the new inbox.
        connecting = true
        defer { connecting = false }
        let email: String
        do {
            email = try await GoogleAuth().signIn(onAuthorized: { status.update(.connecting, job: job) })
        } catch {
            total.end("sign-in failed")
            throw error
        }
        var list = accounts.filter { $0.email != email }
        list.append(GmailAccount(email: email))
        accounts = list
        // That it happened, never which address (Google Limited Use).
        Analytics.shared.track(.gmailConnected, ["accounts": .int(list.count)])
        // Only the new account: the others were synced recently enough.
        let s = try await syncAccounts([email], in: context, force: true, rethrow: true, job: job)
        total.end("added \(s.added)")
        return s
    }

    /// A connect is running (from Google's sheet to the end of its first sync).
    @MainActor private(set) static var connecting = false

    /// Starts `connect` as its own task, so closing the sheet (or the whole
    /// setup screen) doesn't stop it. Progress and errors go to `SyncStatus.gmail`.
    @MainActor
    static func startConnect(in context: ModelContext) {
        let status = SyncStatus.gmail
        guard !status.isBusyForPerson else { return }
        status.task = Task {
            do {
                _ = try await connect(in: context)
            } catch GoogleAuth.AuthError.cancelled {
                status.dismiss()
            } catch is CancellationError {
                status.dismiss()
            } catch {
                status.update(.failed(SyncFailure.from(error)))
            }
        }
    }

    /// A sync the person asked for (Sync Now, Try Again), shown with progress.
    @MainActor
    static func startSync(in context: ModelContext) {
        let status = SyncStatus.gmail
        // Already syncing in the background: just show that one.
        if status.isBusy { status.promote(); return }
        let job = status.begin(quiet: false)
        status.task = Task {
            _ = await exclusive(force: true) {
                (try? await syncAccounts(accounts.map(\.email), in: context, force: true, rethrow: false, job: job)) ?? EmailSync.Summary()
            }
        }
    }

    /// Revokes access. With `deletePurchases`, also removes purchases that
    /// only this Gmail account reported (not ones a tap also logged).
    @MainActor
    static func disconnect(_ account: GmailAccount, deletePurchases: Bool, in context: ModelContext) async {
        await GoogleAuth.disconnect(account.email)
        accounts.removeAll { $0.email == account.email }
        let email = account.email
        // Keeping purchases: keep the list of emails already read too, or
        // reconnecting reads them again and brings back ones the user deleted.
        guard deletePurchases else { return }
        for r in (try? context.fetch(FetchDescriptor<ImportedRecord>(predicate: #Predicate { $0.account == email }))) ?? [] {
            context.delete(r)
        }
        try? context.save()
        let mine = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.sourceAccount == email }))) ?? []
        for t in mine where t.seenIn == [.email] { context.delete(t) }
        try? context.save()
    }

    /// Accounts being synced right now. Opening the app while a connect is
    /// still reading (the Google sheet closing makes the app active again)
    /// must not start a second, identical sync of the same inbox.
    @MainActor private static var inFlight: Set<String> = []

    /// Syncs every connected account (at most every 5 minutes unless forced).
    /// `quiet`: started by the app, not the person; Home only hears about it
    /// when there is something to add or to fix.
    /// `failed` in the result counts accounts whose sync threw, for the
    /// pull-to-refresh note.
    @MainActor @discardableResult
    static func syncAll(in context: ModelContext, force: Bool = false) async -> EmailSync.Summary {
        guard !connecting else { return EmailSync.Summary() }
        #if DEBUG
        if SyncStatus.demoActive { return EmailSync.Summary() }
        #endif
        return await exclusive(force: force) {
            let status = SyncStatus.gmail
            // Something the person started owns the status line: stay invisible.
            let job = status.isBusyForPerson ? -1 : status.begin(quiet: true)
            return (try? await syncAccounts(accounts.map(\.email), in: context, force: force, rethrow: false, job: job)) ?? EmailSync.Summary()
        }
    }

    /// The whole-inbox sync running now. Opening the app, pull-to-refresh
    /// and Sync Now can all ask at once; they share one run instead of
    /// listing and downloading the same emails side by side.
    @MainActor private static var running: (id: Int, force: Bool, task: Task<EmailSync.Summary, Never>)?
    @MainActor private static var runs = 0

    /// Runs `work` unless a sync is already going, in which case it waits
    /// for that one and returns its result. A forced call that finds an
    /// unforced run waits for it, then runs once more: the unforced one may
    /// have skipped accounts synced in the last 5 minutes.
    @MainActor
    static func exclusive(force: Bool, _ work: @escaping @MainActor () async -> EmailSync.Summary) async -> EmailSync.Summary {
        while let current = running {
            let result = await current.task.value
            if !force || current.force { return result }
            // Cleared by the task itself before it finishes; this only guards
            // against spinning if that ever changes.
            if running?.id == current.id { running = nil }
        }
        runs += 1
        let id = runs
        let task = Task { @MainActor in
            let result = await work()
            // Before finishing, so a waiter never finds a done run here.
            if running?.id == id { running = nil }
            return result
        }
        running = (id, force, task)
        return await task.value
    }

    @MainActor
    private static func syncAccounts(_ emails: [String], in context: ModelContext, force: Bool, rethrow: Bool,
                                     job: Int) async throws -> EmailSync.Summary {
        var total = EmailSync.Summary()
        // A build without Gmail never reads the inbox; the account stays
        // until disconnected.
        guard Features.gmail else {
            SyncStatus.gmail.update(.idle, job: job)
            return total
        }
        let status = SyncStatus.gmail
        let report: @MainActor @Sendable (SyncStatus.Phase) -> Void = { status.update($0, job: job) }
        let generation = resetGeneration
        var list = accounts
        var touched: Set<String> = []
        var ran = false
        var failure: Error?
        WidgetBridge.hold()
        defer { WidgetBridge.release() }
        for i in list.indices where emails.contains(list[i].email) {
            guard resetGeneration == generation else { break }
            if !force, let last = list[i].lastSync, Date.now.timeIntervalSince(last) < 300 { continue }
            let email = list[i].email
            guard !inFlight.contains(email) else { continue }
            inFlight.insert(email)
            defer { inFlight.remove(email) }
            ran = true
            touched.insert(email)
            do {
                let started = Date.now
                let s = try await sync(list[i], generation: generation, in: context, report: report, alreadyAdded: total.added)
                total.added += s.added; total.merged += s.merged; total.refunds += s.refunds; total.checked += s.checked
                if s.incomplete {
                    // Hit the 1,000 cap: next time, carry on below the oldest
                    // email reached, rather than listing the same 1,000 again.
                    if list[i].backfillStartedAt == nil { list[i].backfillStartedAt = started }
                    if let oldest = s.oldestListed { list[i].backfillBefore = oldest }
                } else {
                    list[i].lastSync = list[i].backfillStartedAt ?? started
                    list[i].backfillBefore = nil
                    list[i].backfillStartedAt = nil
                }
                list[i].lastResult = s.incomplete ? s.text + " · more next sync" : s.text
            } catch {
                // Stopped by Disconnect or Delete All: not a failure to report.
                let stopped = error is CancellationError
                list[i].lastResult = stopped ? nil : error.localizedDescription
                if !stopped { failure = error; total.failed += 1 }
                log.error("Gmail sync failed for \(list[i].email): \(error.localizedDescription)")
            }
        }
        // Delete All ran during the sync: write nothing back.
        guard resetGeneration == generation else {
            report(.idle)
            return EmailSync.Summary()
        }
        // Accounts may have been connected or disconnected during the sync,
        // and a connect may have synced its own account alongside this one:
        // write back only the accounts this run synced, if still there.
        accounts = accounts.map { a in
            guard touched.contains(a.email) else { return a }
            return list.first { $0.email == a.email } ?? a
        }
        // Whether it worked, and nothing about the inbox: no email counts, no
        // purchase counts (Google Limited Use). Before the throw, so a connect
        // whose first sync fails is counted too.
        if ran {
            var props: [String: Analytics.AnalyticsValue] = ["ok": .bool(failure == nil), "forced": .bool(force)]
            if let failure { props["error_code"] = .string(String(describing: SyncFailure.from(failure).kind)) }
            Analytics.shared.track(.gmailSyncFinished, props)
            if total.added > 0 { Analytics.shared.trackOnce(.activationFirstAutoPurchase, ["source": .string("email")]) }
        }
        if let failure {
            report(.failed(SyncFailure.from(failure)))
            if rethrow { throw failure }
        } else if ran || !status.quiet {
            report(.finished(added: total.added))
        } else if case .failed = status.phase {
            // Nothing ran (synced a moment ago): leave an earlier error showing.
        } else {
            report(.idle)
        }
        if total.added + total.merged + total.refunds > 0 {
            await Perf.measure("fx.afterGmail") { _ = await FXService.backfill(in: context) }
        }
        return total
    }

    @MainActor
    private static func sync(_ account: GmailAccount, generation: Int, in context: ModelContext,
                             report: @escaping @MainActor @Sendable (SyncStatus.Phase) -> Void,
                             alreadyAdded: Int) async throws -> EmailSync.Summary {
        let whole = Perf.begin("gmail.sync")
        let token = try await Perf.measure("gmail.token") { try await GoogleAuth.accessToken(for: account.email) }
        let api = GmailAPI(token: token)
        // A few days of overlap so late-arriving emails aren't missed; already
        // imported ones are skipped by id.
        var since = account.lastSync.map { Int($0.addingTimeInterval(-3 * 86400).timeIntervalSince1970) }
        #if DEBUG
        if ProcessInfo.processInfo.environment["SPEND_GMAIL_FULL"] == "1" { since = nil }
        #endif
        var window = since.map { "after:\($0)" } ?? "newer_than:\(firstSyncDays)d"
        if let before = account.backfillBefore { window += " before:\(Int(before.timeIntervalSince1970))" }
        let search = "((\(EmailParsers.gmailQuery)) OR (\(GenericReceipts.gmailQuery))) \(window)"
        report(.searching(found: 0))
        let listSpan = Perf.begin("gmail.list")
        let (ids, truncated) = try await api.listMessages(query: search) { found in
            await MainActor.run { report(.searching(found: found)) }
        }
        listSpan.end("\(ids.count) ids")

        #if DEBUG
        if ProcessInfo.processInfo.environment["SPEND_GMAIL_RESET"] == "1" {
            let email = account.email
            for t in (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.sourceAccount == email }))) ?? [] { context.delete(t) }
            for r in (try? context.fetch(FetchDescriptor<ImportedRecord>())) ?? [] { context.delete(r) }
            try? context.save()
        }
        #endif
        let fresh = Perf.measure("gmail.skipKnown") { unread(ids, in: context) }

        let email = account.email
        var summary = try await importMessages(
            fresh, api: api, account: email, aiAvailable: ReceiptAI.isAvailable, in: context,
            // Disconnect or Delete All: stop without writing anything back.
            stillConnected: { resetGeneration == generation && accounts.contains { $0.email == email } },
            progress: { done, total, added in report(.adding(done: done, total: total, added: alreadyAdded + added)) })
        #if DEBUG
        print("GMAILDEBUG found=\(ids.count) fresh=\(fresh.count) checked=\(summary.checked) added=\(summary.added) ai=\(ReceiptAI.isAvailable)")
        #endif
        log.info("Gmail sync: \(ids.count) found, \(fresh.count) new, \(summary.added) added")
        summary.incomplete = truncated
        // Where the next catch-up pass starts: the oldest email in this list.
        if truncated, let last = ids.last { summary.oldestListed = try? await api.messageDate(last) }
        whole.end("\(ids.count) listed, \(fresh.count) fetched, \(summary.added) added")
        return summary
    }

    /// The listed ids not read before, newest first (Gmail's order). Gmail
    /// ids are hex (never contain "-"). "-none" rows only count for the
    /// current reader version, so a reader fix re-reads old misses.
    @MainActor
    static func unread(_ ids: [String], in context: ModelContext) -> [String] {
        let done = Set(((try? context.fetch(FetchDescriptor<ImportedRecord>())) ?? []).compactMap { r -> String? in
            if r.id.contains("-none") && !r.id.hasSuffix("-none-v\(readerVersion)") { return nil }
            return r.id.components(separatedBy: "-").first
        })
        var seen = Set<String>()
        return ids.filter { !done.contains($0) && seen.insert($0).inserted }
    }

    /// One downloaded email, already read by the exact rules when its sender
    /// has them (that runs off the main thread, next to the download).
    nonisolated struct Fetched: Sendable {
        let message: EmailParsers.Message
        /// What was read already. nil: waits for the on-device model.
        let ruled: [EmailRecord]?
        /// Read by the best reader for it (exact rules), so an empty result
        /// really means "not a receipt".
        var exact = false
    }

    /// Downloads, reads and saves emails newest first, a few at a time.
    ///
    /// - Up to `api.concurrency` downloads run at once; a new one starts as
    ///   soon as one finishes (no waiting for the slowest of a batch).
    /// - Purchases are saved every `flushEvery` emails or `flushInterval`
    ///   seconds, so they appear on Home while the rest is still coming, and
    ///   a pause or error keeps what was already read.
    /// - Refunds and DoorDash "order adjusted" emails need their purchase to
    ///   be in first. They wait to the end and go in oldest first.
    @MainActor
    static func importMessages(_ ids: [String], api: GmailAPI, account: String, aiAvailable: Bool,
                               in context: ModelContext, flushEvery: Int = 10, flushInterval: Double = 1.0,
                               stillConnected: () -> Bool = { true },
                               progress: (_ done: Int, _ total: Int, _ added: Int) -> Void = { _, _, _ in }) async throws -> EmailSync.Summary {
        var summary = EmailSync.Summary()
        guard !ids.isEmpty else { return summary }
        let span = Perf.begin("gmail.fetchAndImport")
        var buffer: [EmailRecord] = []
        var notReceipts: [String] = []
        var later: [EmailRecord] = []
        var done = 0
        var lastFlush = ContinuousClock.now
        var readTime = 0.0, saveTime = 0.0

        func flush() throws {
            guard !buffer.isEmpty || !notReceipts.isEmpty else { return }
            // Disconnect or Delete All may have run while this was
            // downloading. Stop without writing anything back.
            guard stillConnected() else { throw CancellationError() }
            let t = ContinuousClock.now
            for id in notReceipts { context.insert(ImportedRecord(id: id, account: account)) }
            let s = try EmailSync.importRecords(buffer, in: context, account: account)
            summary.added += s.added; summary.merged += s.merged; summary.refunds += s.refunds
            buffer = []; notReceipts = []
            lastFlush = .now
            saveTime += Perf.ms(since: t)
        }

        func handle(_ f: Fetched) async {
            let t = ContinuousClock.now
            let m = f.message
            let found: [EmailRecord]
            if let ruled = f.ruled { found = ruled } else { found = await readUnknown(m, aiAvailable: aiAvailable) }
            readTime += Perf.ms(since: t)
            for r in found {
                let adjusted = r.platform == "doordash" && (r.note ?? "").contains("order adjusted")
                if r.kind == "refund" || adjusted { later.append(r) } else { buffer.append(r) }
            }
            // Not a receipt: remember it so it isn't downloaded again —
            // but only when the best reader for it actually ran.
            let bestRan = f.exact || aiAvailable
            if found.isEmpty && bestRan && !m.body.isEmpty {
                notReceipts.append("\(m.id)-none-v\(readerVersion)")
            }
            #if DEBUG
            let layer = f.exact ? "rule" : (aiAvailable ? "ai" : "fallback")
            let got = found.map { "\($0.kind) \($0.merchant) \($0.currency) \($0.amount)" }
            if let dump = ProcessInfo.processInfo.environment["SPEND_GMAIL_DUMP"], m.from.contains(dump) || m.subject.contains(dump) {
                print("GMAILDEBUG body(\(m.subject.prefix(30))) = \(EmailParsers.normalize(m.body).prefix(1500))")
            }
            print("GMAILDEBUG [\(layer)] \(m.from.components(separatedBy: "<").first ?? "") | \(m.subject.prefix(45)) -> \(got.isEmpty ? "skipped" : got.joined(separator: "; "))")
            #endif
        }

        progress(0, ids.count, 0)
        do {
            try await withThrowingTaskGroup(of: Fetched?.self) { group in
                var next = 0
                func startNext() {
                    guard next < ids.count else { return }
                    let id = ids[next]
                    next += 1
                    group.addTask { try await fetchAndRule(id, api: api, aiAvailable: aiAvailable) }
                }
                for _ in 0..<min(api.concurrency, ids.count) { startNext() }
                while let f = try await group.next() {
                    startNext()
                    if let f { await handle(f) }
                    done += 1
                    summary.checked += 1
                    if buffer.count + notReceipts.count >= flushEvery
                        || Perf.ms(since: lastFlush) >= flushInterval * 1000 {
                        try flush()
                    }
                    progress(done, ids.count, summary.added)
                }
            }
            try flush()
        } catch {
            // Keep what was read before the error; the rest comes next sync.
            if !(error is CancellationError) { try? flush() }
            span.end("stopped after \(done)")
            throw error
        }
        if !later.isEmpty {
            // Oldest first, so an adjusted order finds the one it changes.
            buffer = later.sorted { $0.date < $1.date }
            try flush()
        }
        progress(done, ids.count, summary.added)
        span.end("\(ids.count) emails, read \(Int(readTime)) ms, save \(Int(saveTime)) ms")
        return summary
    }

    /// Download one email and read it right there, off the main thread,
    /// unless it needs the on-device model.
    nonisolated static func fetchAndRule(_ id: String, api: GmailAPI, aiAvailable: Bool) async throws -> Fetched? {
        guard let m = try await api.message(id) else { return nil }
        if EmailParsers.knowsSender(m.from) { return Fetched(message: m, ruled: EmailParsers.parse(m), exact: true) }
        if aiAvailable { return Fetched(message: m, ruled: nil) }
        // Anyone can send an email that says "refund". Only senders with
        // exact rules (banks, card alerts) may mark a purchase as refunded.
        let plain = GenericReceipts.parse(m).map { [$0] }?.filter { $0.kind != "refund" } ?? []
        return Fetched(message: m, ruled: plain)
    }

    /// Someone without exact rules: the on-device model first; if it finds
    /// nothing, the plain rule gets a try (both skip shipping updates,
    /// declined payments and so on). Apple's rules for AI in finance: the
    /// person checks what the model read. Anyone can send an email that says
    /// "refund", so only senders with exact rules may mark one refunded.
    @MainActor
    private static func readUnknown(_ m: EmailParsers.Message, aiAvailable: Bool) async -> [EmailRecord] {
        var found: [EmailRecord]
        if aiAvailable, var r = await ReceiptAI.read(m) {
            r.note = "Read by on-device AI · check the amount and shop"
            found = [r]
        } else {
            found = GenericReceipts.parse(m).map { [$0] } ?? []
        }
        found.removeAll { $0.kind == "refund" }
        return found
    }

    /// Known sender → exact rules. Anyone else → on-device AI if the phone
    /// has it, else the plain "Total" rule.
    static func read(_ m: EmailParsers.Message) async -> [EmailRecord] {
        if EmailParsers.knowsSender(m.from) { return EmailParsers.parse(m) }
        return await readUnknown(m, aiAvailable: ReceiptAI.isAvailable)
    }

    // MARK: Gmail API

    nonisolated struct MessageResponse: Decodable {
        struct Header: Decodable { let name: String; let value: String }
        struct Body: Decodable { let data: String? }
        struct Part: Decodable {
            let mimeType: String?
            let headers: [Header]?
            let body: Body?
            let parts: [Part]?
        }
        let id: String
        let internalDate: String?
        let payload: Part
    }

    /// Bump when a reader improves, so emails it missed are read again.
    static let readerVersion = 2

    nonisolated static func message(from m: MessageResponse) -> EmailParsers.Message? {
        let headers = m.payload.headers ?? []
        func header(_ name: String) -> String { headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value ?? "" }
        let date = m.internalDate.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) } ?? .now
        var msg = EmailParsers.Message(id: m.id, from: header("From"), subject: header("Subject"),
                                       body: bodyText(m.payload), date: date)
        // Only Gmail's own result counts. It's the top one; a sender can add
        // fake ones further down, so anything that isn't Gmail's is ignored.
        if let gmail = headers.first(where: { $0.name.caseInsensitiveCompare("Authentication-Results") == .orderedSame }),
           gmail.value.lowercased().hasPrefix("mx.google.com") {
            msg.authenticatedDomains = authenticatedDomains(gmail.value)
        }
        return msg
    }

    /// Domains with a DKIM or DMARC pass in an Authentication-Results header:
    /// "dkim=pass header.i=@apple.com", "dmarc=pass (…) header.from=apple.com".
    nonisolated static func authenticatedDomains(_ results: String) -> Set<String> {
        var out = Set<String>()
        for part in results.lowercased().split(separator: ";") {
            let p = part.trimmingCharacters(in: .whitespaces)
            guard p.hasPrefix("dkim=pass") || p.hasPrefix("dmarc=pass") else { continue }
            for key in ["header.i=", "header.d=", "header.from="] {
                guard let r = p.range(of: key) else { continue }
                let value = p[r.upperBound...].prefix { !$0.isWhitespace && $0 != ";" }
                let domain = value.split(separator: "@").last.map(String.init) ?? ""
                if !domain.isEmpty { out.insert(domain) }
            }
        }
        return out
    }

    /// The plain-text part if there is one; otherwise the HTML turned into text.
    nonisolated static func bodyText(_ part: MessageResponse.Part) -> String {
        if let plain = find(part, "text/plain") { return plain }
        if let html = find(part, "text/html") { return htmlToText(html) }
        return ""
    }

    nonisolated private static func find(_ part: MessageResponse.Part, _ type: String) -> String? {
        if part.mimeType == type, let d = part.body?.data, let data = Data(base64URL: d) {
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        }
        for p in part.parts ?? [] { if let hit = find(p, type) { return hit } }
        return nil
    }

    /// Rough HTML → text, enough for receipts: drop style/script, turn rows
    /// and breaks into new lines and cells into " | ", decode common entities.
    nonisolated static func htmlToText(_ html: String) -> String {
        var s = html
        for (pattern, replacement) in [
            (#"(?is)<(style|script|head)[^>]*>.*?</\1>"#, " "),
            (#"(?i)<br\s*/?>|</p>|</div>|</tr>|</h\d>|</li>"#, "\n"),
            (#"(?i)</td>|</th>"#, " | "),
            (#"<[^>]+>"#, " "),
        ] {
            s = s.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
                        "&#36;": "$", "&bull;": "•", "&middot;": "·", "&ndash;": "–", "&mdash;": "—", "&rsquo;": "’"]
        for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
        return s
    }
}

/// The few Gmail REST calls Sortd makes. The session, the pause between
/// retries and how many downloads run at once can be swapped in tests.
nonisolated struct GmailAPI: Sendable {
    var token: String
    var session: URLSession = GoogleAuth.session
    var base = "https://gmail.googleapis.com/gmail/v1/users/me/messages"
    /// Downloads at once. Gmail allows 250 quota units per user per second
    /// and one email costs 5, so 6 in flight (about 20–30 a second) stays
    /// well inside it, with room for a second account syncing.
    var concurrency = 6
    /// Waits after "too fast" (429, or 403 rateLimitExceeded), doubling,
    /// plus a little random spread so parallel downloads don't retry together.
    var backoff: [Double] = [1, 2, 4, 8]
    var sleep: @Sendable (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }

    private struct ListResponse: Decodable {
        struct Ref: Decodable { let id: String }
        let messages: [Ref]?
        let nextPageToken: String?
    }
    private struct DateOnly: Decodable { let internalDate: String? }

    /// Message ids matching the search, newest first, capped at 1,000.
    /// 500 per page (Gmail's most), so the cap is 2 round trips, not 10.
    /// `found` hears the running count, for "found N".
    func listMessages(query: String, found: @Sendable (Int) async -> Void = { _ in }) async throws -> ([String], Bool) {
        var ids: [String] = []
        var page: String?
        repeat {
            var url = URLComponents(string: base)!
            url.queryItems = [.init(name: "q", value: query), .init(name: "maxResults", value: "500"),
                              .init(name: "fields", value: "messages/id,nextPageToken")]
            if let page { url.queryItems?.append(.init(name: "pageToken", value: page)) }
            // URLComponents leaves "+" alone, and servers read it as a space:
            // "invoice+statements@…" would become two words and the whole
            // OR-search would match nothing. Encode it.
            url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            let r: ListResponse = try await get(url.url!)
            ids += (r.messages ?? []).map(\.id)
            page = r.nextPageToken
            await found(ids.count)
        } while page != nil && ids.count < 1000
        return (ids, page != nil)
    }

    /// One email, full body. nil when it was deleted after the list.
    func message(_ id: String) async throws -> EmailParsers.Message? {
        // Only the parts Sortd reads: skips the snippet, labels, size and history.
        let url = URL(string: "\(base)/\(id)?format=full&fields=id,internalDate,payload")!
        do {
            let m: GmailSync.MessageResponse = try await get(url)
            return GmailSync.message(from: m)
        } catch let e as GmailError where e.code == 404 {
            return nil
        }
    }

    /// When one email arrived, without downloading it.
    func messageDate(_ id: String) async throws -> Date? {
        let url = URL(string: "\(base)/\(id)?format=minimal&fields=internalDate")!
        let m: DateOnly = try await get(url)
        return m.internalDate.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    /// GET with retries when Gmail says "too fast" (quota / rate limit) or
    /// has a passing server error. Honours Retry-After when Gmail sends one.
    func get<T: Decodable>(_ url: URL) async throws -> T {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 30
        var attempt = 0
        while true {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: req)
            let http = response as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            if code == 200 { return try JSONDecoder().decode(T.self, from: data) }
            let retryable = code == 429 || (code == 403 && Self.isRateLimit(data)) || code == 500 || code == 503
            if retryable, attempt < backoff.count {
                let asked = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                let wait = min(asked ?? backoff[attempt] * Double.random(in: 1...1.3), 30)
                attempt += 1
                try await sleep(wait)
                continue
            }
            // Google's reason, e.g. "insufficientPermissions" or "rateLimitExceeded".
            let reason = String(data: data, encoding: .utf8) ?? ""
            #if DEBUG
            print("GMAILDEBUG http \(code) \(reason.prefix(400))")
            #endif
            throw GmailError(code: code, body: reason)
        }
    }

    static func isRateLimit(_ data: Data) -> Bool {
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.contains("rateLimit") || text.contains("Quota exceeded")
    }
}

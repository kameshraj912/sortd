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

    /// Signs in and runs the first sync.
    @MainActor
    static func connect(in context: ModelContext) async throws -> EmailSync.Summary {
        let email = try await GoogleAuth().signIn()
        var list = accounts.filter { $0.email != email }
        list.append(GmailAccount(email: email))
        accounts = list
        return await syncAll(in: context, force: true)
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

    /// Syncs every connected account (at most every 5 minutes unless forced).
    @MainActor @discardableResult
    static func syncAll(in context: ModelContext, force: Bool = false) async -> EmailSync.Summary {
        var total = EmailSync.Summary()
        // Gmail receipts are Pro. A lapsed subscription (or a build without
        // Gmail) stops reading the inbox; the account stays until disconnected.
        guard Features.gmail, ProStore.shared.isPro else { return total }
        let generation = resetGeneration
        var list = accounts
        for i in list.indices {
            guard resetGeneration == generation else { break }
            if !force, let last = list[i].lastSync, Date.now.timeIntervalSince(last) < 300 { continue }
            do {
                let started = Date.now
                let s = try await sync(list[i], generation: generation, in: context)
                total.added += s.added; total.merged += s.merged; total.refunds += s.refunds
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
                total.failed += 1
                list[i].lastResult = error.localizedDescription
                log.error("Gmail sync failed for \(list[i].email): \(error.localizedDescription)")
            }
        }
        // Delete All ran during the sync: write nothing back.
        guard resetGeneration == generation else { return EmailSync.Summary() }
        // Accounts may have been connected or disconnected during the sync:
        // update only the ones that are still there.
        accounts = accounts.map { a in list.first { $0.email == a.email } ?? a }
        if total.added + total.merged + total.refunds > 0 { await FXService.backfill(in: context) }
        return total
    }

    @MainActor
    private static func sync(_ account: GmailAccount, generation: Int,
                             in context: ModelContext) async throws -> EmailSync.Summary {
        let token = try await GoogleAuth.accessToken(for: account.email)
        // A few days of overlap so late-arriving emails aren't missed; already
        // imported ones are skipped by id.
        var since = account.lastSync.map { Int($0.addingTimeInterval(-3 * 86400).timeIntervalSince1970) }
        #if DEBUG
        if ProcessInfo.processInfo.environment["SORTD_GMAIL_FULL"] == "1" { since = nil }
        #endif
        var window = since.map { "after:\($0)" } ?? "newer_than:\(firstSyncDays)d"
        if let before = account.backfillBefore { window += " before:\(Int(before.timeIntervalSince1970))" }
        let search = "((\(EmailParsers.gmailQuery)) OR (\(GenericReceipts.gmailQuery))) \(window)"
        let (ids, truncated) = try await listMessages(query: search, token: token)

        #if DEBUG
        if ProcessInfo.processInfo.environment["SORTD_GMAIL_RESET"] == "1" {
            let email = account.email
            for t in (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.sourceAccount == email }))) ?? [] { context.delete(t) }
            for r in (try? context.fetch(FetchDescriptor<ImportedRecord>())) ?? [] { context.delete(r) }
            try? context.save()
        }
        #endif
        // Gmail ids are hex (never contain "-"). "-none" rows only count for
        // the current reader version, so a reader fix re-reads old misses.
        let done = Set(((try? context.fetch(FetchDescriptor<ImportedRecord>())) ?? []).compactMap { r -> String? in
            if r.id.contains("-none") && !r.id.hasSuffix("-none-v\(readerVersion)") { return nil }
            return r.id.components(separatedBy: "-").first
        })
        // Oldest first, so a purchase is in before its refund.
        let fresh = Array(ids.filter { !done.contains($0) }.reversed())

        // 20 at a time, saving after each batch: a pause or error keeps what
        // was already read, and the next sync carries on from there.
        var summary = EmailSync.Summary()
        for start in stride(from: 0, to: fresh.count, by: 20) {
            let batch = Array(fresh[start..<min(start + 20, fresh.count)])
            let messages = try await fetchMessages(batch, token: token)
            var records: [EmailRecord] = []
            var notReceipts: [String] = []
            for m in messages {
                let found = await read(m)
                records += found
                // Not a receipt: remember it so it isn't downloaded again —
                // but only when the best reader for it actually ran.
                let bestRan = EmailParsers.knowsSender(m.from) || ReceiptAI.isAvailable
                if found.isEmpty && bestRan && !m.body.isEmpty {
                    notReceipts.append("\(m.id)-none-v\(readerVersion)")
                }
                #if DEBUG
                let layer = EmailParsers.knowsSender(m.from) ? "rule" : (ReceiptAI.isAvailable ? "ai" : "fallback")
                let got = found.map { "\($0.kind) \($0.merchant) \($0.currency) \($0.amount)" }
                if let dump = ProcessInfo.processInfo.environment["SORTD_GMAIL_DUMP"], m.from.contains(dump) || m.subject.contains(dump) {
                    print("GMAILDEBUG body(\(m.subject.prefix(30))) = \(EmailParsers.normalize(m.body).prefix(1500))")
                }
                print("GMAILDEBUG [\(layer)] \(m.from.components(separatedBy: "<").first ?? "") | \(m.subject.prefix(45)) -> \(got.isEmpty ? "skipped" : got.joined(separator: "; "))")
                #endif
            }
            // Disconnect or Delete All may have run while this batch was
            // downloading. Stop without writing anything back.
            guard resetGeneration == generation,
                  accounts.contains(where: { $0.email == account.email }) else { throw CancellationError() }
            for id in notReceipts { context.insert(ImportedRecord(id: id, account: account.email)) }
            let s = try EmailSync.importRecords(records, in: context, account: account.email)
            summary.added += s.added; summary.merged += s.merged; summary.refunds += s.refunds
            summary.checked += messages.count
        }
        #if DEBUG
        print("GMAILDEBUG found=\(ids.count) fresh=\(fresh.count) checked=\(summary.checked) added=\(summary.added) ai=\(ReceiptAI.isAvailable)")
        #endif
        log.info("Gmail sync: \(ids.count) found, \(fresh.count) new, \(summary.added) added")
        summary.incomplete = truncated
        // Where the next catch-up pass starts: the oldest email in this list.
        if truncated, let last = ids.last { summary.oldestListed = try? await messageDate(last, token: token) }
        return summary
    }

    /// Known sender → exact rules. Anyone else → on-device AI if the phone
    /// has it, else the plain "Total" rule.
    static func read(_ m: EmailParsers.Message) async -> [EmailRecord] {
        if EmailParsers.knowsSender(m.from) { return EmailParsers.parse(m) }
        // The model first; if it finds nothing, the plain rule gets a try
        // (both skip shipping updates, declined payments and so on).
        var found: [EmailRecord]
        if ReceiptAI.isAvailable, var r = await ReceiptAI.read(m) {
            // Apple's rules for AI in finance: the person checks what the model read.
            r.note = "Read by on-device AI · check the amount and shop"
            found = [r]
        } else {
            found = GenericReceipts.parse(m).map { [$0] } ?? []
        }
        // Anyone can send an email that says "refund". Only senders with
        // exact rules (banks, card alerts) may mark a purchase as refunded.
        found.removeAll { $0.kind == "refund" }
        return found
    }

    nonisolated private static func isRateLimit(_ data: Data) -> Bool {
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.contains("rateLimit") || text.contains("Quota exceeded")
    }

    // MARK: Gmail API

    nonisolated private struct ListResponse: Decodable {
        struct Ref: Decodable { let id: String }
        let messages: [Ref]?
        let nextPageToken: String?
    }

    /// Message ids matching the search, newest first (capped at 500).
    /// Bump when a reader improves, so emails it missed are read again.
    static let readerVersion = 2

    nonisolated private static func listMessages(query: String, token: String) async throws -> ([String], Bool) {
        var ids: [String] = []
        var page: String?
        repeat {
            var url = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
            url.queryItems = [.init(name: "q", value: query), .init(name: "maxResults", value: "100")]
            if let page { url.queryItems?.append(.init(name: "pageToken", value: page)) }
            // URLComponents leaves "+" alone, and servers read it as a space:
            // "invoice+statements@…" would become two words and the whole
            // OR-search would match nothing. Encode it.
            url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            let r: ListResponse = try await get(url.url!, token: token)
            ids += (r.messages ?? []).map(\.id)
            page = r.nextPageToken
        } while page != nil && ids.count < 1000
        return (ids, page != nil)
    }

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

    nonisolated private struct DateOnly: Decodable { let internalDate: String? }

    /// When one email arrived, without downloading it.
    nonisolated private static func messageDate(_ id: String, token: String) async throws -> Date? {
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=minimal")!
        let m: DateOnly = try await get(url, token: token)
        return m.internalDate.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    /// Full messages, 4 at a time (kind to Gmail's per-user limits).
    nonisolated private static func fetchMessages(_ ids: [String], token: String) async throws -> [EmailParsers.Message] {
        var out: [EmailParsers.Message] = []
        for chunk in stride(from: 0, to: ids.count, by: 4).map({ Array(ids[$0..<min($0 + 4, ids.count)]) }) {
            try await withThrowingTaskGroup(of: EmailParsers.Message?.self) { group in
                for id in chunk {
                    group.addTask {
                        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=full")!
                        let m: MessageResponse = try await get(url, token: token)
                        return message(from: m)
                    }
                }
                for try await m in group { if let m { out.append(m) } }
            }
        }
        return out
    }

    nonisolated private static func message(from m: MessageResponse) -> EmailParsers.Message? {
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

    /// GET with retries when Gmail says "too fast" (quota / rate limit).
    nonisolated private static func get<T: Decodable>(_ url: URL, token: String) async throws -> T {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var (data, response) = try await GoogleAuth.session.data(for: req)
        var code = (response as? HTTPURLResponse)?.statusCode ?? 0
        for wait in [2.0, 5.0, 10.0] where code == 429 || (code == 403 && isRateLimit(data)) {
            try await Task.sleep(for: .seconds(wait))
            (data, response) = try await GoogleAuth.session.data(for: req)
            code = (response as? HTTPURLResponse)?.statusCode ?? 0
        }
        guard code == 200 else {
            // Google's reason, e.g. "insufficientPermissions" or "rateLimitExceeded".
            let reason = String(data: data, encoding: .utf8) ?? ""
            #if DEBUG
            print("GMAILDEBUG http \(code) \(reason.prefix(400))")
            #endif
            throw GmailError(code: code, body: reason)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

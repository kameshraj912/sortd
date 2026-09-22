import CryptoKit
import Foundation
import Observation
import SwiftData

/// One forwarded email as the Worker sends it, after the phone decrypts it.
/// Only what the parsers need. Matches `buildPayload` in inbox/src/email.js.
nonisolated struct InboxPayload: Codable, Equatable, Sendable {
    struct Auth: Codable, Equatable, Sendable {
        /// Domains with a valid DKIM signature on this exact message.
        var dkim: [String] = []
        /// From domains with DMARC p=reject that Cloudflare enforced (only when the owner turns that on).
        var dmarc: [String] = []
    }
    struct Confirm: Codable, Equatable, Sendable {
        var code: String?
        var url: String?
    }

    var v: Int
    var kind: String
    var messageId: String?
    var from: String
    var subject: String
    var date: String
    var text: String?
    var html: String?
    var auth: Auth?
    var confirm: Confirm?

    static let mail = "mail"
    static let gmailConfirmation = "gmail-forwarding-confirmation"
}

/// Google's "confirm forwarding" request, waiting for the person to tap.
nonisolated struct GmailForwardingRequest: Codable, Equatable, Sendable {
    var code: String?
    /// Always https://mail-settings.google.com/mail/vf-… (checked before it gets here).
    /// Only set when google.com's DKIM signature proved Google sent it.
    var url: URL?
    /// The Gmail address asking to forward, from Google's subject line. Only when proven.
    var requestedBy: String?
    /// google.com signed it. Without that, only the code is shown: typing a code
    /// into your own Gmail can't approve someone else's forwarding, but tapping
    /// their link could.
    var verified: Bool = false
    var receivedAt: Date
}

/// Where the inbox keeps its secrets. The Keychain in the app, memory in tests.
nonisolated struct InboxSecrets: Sendable {
    var get: @Sendable (String) -> String?
    var set: @Sendable (String, String) -> Void
    var delete: @Sendable (String) -> Void

    static let keychain = InboxSecrets(get: { Keychain.get($0) }, set: { Keychain.set($1, for: $0) }, delete: { Keychain.delete($0) })

    static func memory() -> InboxSecrets {
        final class Box: @unchecked Sendable { var values: [String: String] = [:]; let lock = NSLock() }
        let box = Box()
        return InboxSecrets(
            get: { k in box.lock.withLock { box.values[k] } },
            set: { k, v in box.lock.withLock { box.values[k] = v } },
            delete: { k in _ = box.lock.withLock { box.values.removeValue(forKey: k) } })
    }
}

/// The receipt-forwarding inbox: a private address like
/// `r7k2x9…@in.sortd.page` that Gmail or Outlook forwards receipts to.
///
/// No Google sign-in. The server only ever holds each email encrypted to this
/// phone's key, for at most 24 hours; the phone downloads it, decrypts it,
/// reads it with the same parsers as Gmail sync, then deletes it from the
/// server. See docs/ForwardingInbox.md.
///
/// Not wired into Settings or the app's refresh yet. To wire it:
/// - Settings: `NavigationLink("Forwarding Inbox") { ForwardingInboxView() }`
/// - On open (the `.task(id: scenePhase)` in SpendApp): `await ForwardingInbox.shared.syncIfOn(in: context)`
/// - Delete All Data (DataReset), before `Keychain.deleteAll()`: `await ForwardingInbox.shared.turnOff(deletePurchases: false, in: context)`
@MainActor
@Observable
final class ForwardingInbox {
    static let shared = ForwardingInbox()

    /// Stored in `ImportedRecord.account` and `Transaction.sourceAccount`, like a Gmail address.
    static let account = "forwarding-inbox"
    /// Checks on open are skipped if the last one was this recent.
    static let minimumGap: TimeInterval = 60

    private enum K {
        static let key = "inbox-key"
        static let token = "inbox-token"
        static let address = "inboxAddress"
        static let request = "inboxGmailRequest"
        static let lastCheck = "inboxLastCheck"
        static let lastResult = "inboxLastResult"
        /// A turn-off the server hasn't heard about yet (offline at the time).
        static let pendingOff = "inbox-pending-off"
    }

    private let client: InboxClient
    private let secrets: InboxSecrets
    private let defaults: UserDefaults

    private(set) var address: String?
    private(set) var gmailRequest: GmailForwardingRequest?
    private(set) var lastCheck: Date?
    private(set) var lastResult: String?
    private(set) var busy = false

    init(client: InboxClient = .live, secrets: InboxSecrets = .keychain, defaults: UserDefaults = .standard) {
        self.client = client
        self.secrets = secrets
        self.defaults = defaults
        address = defaults.string(forKey: K.address)
        gmailRequest = defaults.data(forKey: K.request).flatMap { try? JSONDecoder().decode(GmailForwardingRequest.self, from: $0) }
        // Google's link stops working after a while; don't keep showing an old one.
        if let r = gmailRequest, r.receivedAt < .now.addingTimeInterval(-7 * 86400) { dismissGmailRequest() }
        lastCheck = defaults.object(forKey: K.lastCheck) as? Date
        lastResult = defaults.string(forKey: K.lastResult)
    }

    var isOn: Bool { credentials != nil && key != nil }

    /// The page the QR code opens. The address goes after "#", which the
    /// browser never sends to the server.
    var setupURL: URL? {
        guard let address else { return nil }
        var c = URLComponents(url: client.base.appending(path: "setup"), resolvingAgainstBaseURL: false)
        c?.fragment = "a=\(address)"
        return c?.url
    }

    private var credentials: InboxClient.Credentials? {
        guard let address, let token = secrets.get(K.token) else { return nil }
        return .init(address: address, token: token)
    }

    private var key: InboxCrypto.Key? {
        secrets.get(K.key).flatMap { try? InboxCrypto.Key(stored: $0) }
    }

    // MARK: Turning on and off

    /// Makes a key pair, registers the public half, and saves the address.
    @discardableResult
    func turnOn() async throws -> String {
        await waitUntilIdle()
        if isOn, let address { return address }
        busy = true
        defer { busy = false }
        await retryPendingTurnOff()
        let key = try InboxCrypto.Key.generate()
        let reg = try await client.register(publicKey: key.publicKey)
        secrets.set(K.key, key.stored)
        secrets.set(K.token, reg.token)
        defaults.set(reg.address, forKey: K.address)
        address = reg.address
        setResult(nil)
        return reg.address
    }

    /// A fresh address and key. The old address stops working within about a minute.
    @discardableResult
    func newAddress() async throws -> String {
        await turnOff(deletePurchases: false, in: nil)
        return try await turnOn()
    }

    /// Deletes the mailbox on the server (and everything waiting in it) and
    /// forgets the key. If the server can't be reached, it's retried on the
    /// next `turnOn` or check. With `deletePurchases`, also removes purchases
    /// that only the forwarding inbox reported.
    func turnOff(deletePurchases: Bool, in context: ModelContext?) async {
        // Let a check in progress finish first, or it could put back purchases
        // this is about to delete.
        await waitUntilIdle()
        busy = true
        defer { busy = false }
        if let c = credentials {
            do { try await client.turnOff(c) } catch let e as InboxClient.Failure where e.status == 401 {
                // Already gone on the server.
            } catch {
                if let data = try? JSONEncoder().encode(c) { secrets.set(K.pendingOff, String(decoding: data, as: UTF8.self)) }
            }
        }
        secrets.delete(K.key)
        secrets.delete(K.token)
        defaults.removeObject(forKey: K.address)
        address = nil
        dismissGmailRequest()
        setResult(nil)
        guard deletePurchases, let context else { return }
        let account = Self.account
        for r in (try? context.fetch(FetchDescriptor<ImportedRecord>(predicate: #Predicate { $0.account == account }))) ?? [] {
            context.delete(r)
        }
        let mine = (try? context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { $0.sourceAccount == account }))) ?? []
        for t in mine where t.seenIn == [.email] { context.delete(t) }
        try? context.save()
    }

    func retryPendingTurnOff() async {
        guard let text = secrets.get(K.pendingOff),
              let c = try? JSONDecoder().decode(InboxClient.Credentials.self, from: Data(text.utf8)) else { return }
        do {
            try await client.turnOff(c)
        } catch let e as InboxClient.Failure where e.status == 401 {
            // Already gone on the server: nothing left to retry.
        } catch {
            return   // still offline; try again next time
        }
        secrets.delete(K.pendingOff)
    }

    func dismissGmailRequest() {
        gmailRequest = nil
        defaults.removeObject(forKey: K.request)
    }

    // MARK: Checking for mail

    /// For app open. Pro only, like Gmail receipts; at most once a minute.
    @discardableResult
    func syncIfOn(in context: ModelContext, force: Bool = false) async -> EmailSync.Summary? {
        await retryPendingTurnOff()
        guard isOn, ProStore.shared.isPro, !busy else { return nil }
        if !force, let lastCheck, Date.now.timeIntervalSince(lastCheck) < Self.minimumGap { return nil }
        return try? await sync(in: context)
    }

    /// Downloads everything waiting, decrypts it, imports the purchases, then
    /// deletes from the server what was read. A message that can't be
    /// decrypted is left alone and expires on the server within 24 hours.
    @discardableResult
    func sync(in context: ModelContext) async throws -> EmailSync.Summary {
        guard !busy, let creds = credentials, let key else { return EmailSync.Summary() }
        busy = true
        defer { busy = false }
        var total = EmailSync.Summary()
        var unreadable = 0
        var cursor: String?
        do {
            for _ in 0..<20 {   // 20 pages x 20 = 400 messages; the server caps a mailbox at 100 waiting
                let page = try await client.list(creds, cursor: cursor)
                var opened: [(id: String, payload: InboxPayload)] = []
                for m in page.messages {
                    guard let p = Self.open(m, with: key) else { unreadable += 1; continue }
                    opened.append((m.id, p))
                }
                for (_, p) in opened where p.kind == InboxPayload.gmailConfirmation {
                    if let r = Self.gmailRequest(from: p) { saveGmailRequest(r) }
                }
                let s = try await Self.importPayloads(opened.map(\.payload).filter { $0.kind == InboxPayload.mail }, in: context)
                total.added += s.added; total.merged += s.merged; total.refunds += s.refunds; total.skipped += s.skipped
                total.checked += opened.count
                // Saved first (importRecords saves), deleted second: a crash in
                // between means reading it again, which the import ids skip.
                for (id, _) in opened { try? await client.delete(id, creds) }
                guard page.more, let next = page.cursor else { break }
                cursor = next
            }
        } catch let e as InboxClient.Failure where e.status == 401 {
            setResult(e.localizedDescription)
            throw e
        }
        var text = total.text
        if unreadable > 0 { text += " · \(unreadable) couldn't be opened" }
        setResult(text)
        if total.added + total.merged + total.refunds > 0 { await FXService.backfill(in: context) }
        log.info("Forwarding inbox: \(total.checked) read, \(total.added) added, \(unreadable) unreadable")
        return total
    }

    /// One thing at a time: turning on, checking, turning off.
    private func waitUntilIdle() async {
        while busy { try? await Task.sleep(for: .milliseconds(50)) }
    }

    private func setResult(_ text: String?) {
        lastResult = text
        lastCheck = text == nil ? nil : .now
        defaults.set(lastResult, forKey: K.lastResult)
        defaults.set(lastCheck, forKey: K.lastCheck)
    }

    private func saveGmailRequest(_ r: GmailForwardingRequest) {
        gmailRequest = r
        defaults.set(try? JSONEncoder().encode(r), forKey: K.request)
    }

    // MARK: Pure steps (tested directly)

    /// Decrypts one envelope. Nil if it isn't for this key or isn't a payload we understand.
    nonisolated static func open(_ m: InboxClient.Envelope, with key: InboxCrypto.Key) -> InboxPayload? {
        guard let enc = Data(base64URL: m.enc), let ct = Data(base64URL: m.ct),
              let plain = try? key.open(enc: enc, ciphertext: ct, aad: Data(m.id.utf8)),
              let p = try? JSONDecoder().decode(InboxPayload.self, from: plain), p.v == 1 else { return nil }
        return p
    }

    /// The payload as the parsers' message type. `authenticatedDomains` is
    /// never nil here: nil would mean "the source can't tell", which lets a
    /// bank's parser run on the sender address alone. For forwarded mail
    /// only a proven domain counts.
    nonisolated static func message(from p: InboxPayload) -> EmailParsers.Message {
        let body = p.text ?? p.html.map(GmailSync.htmlToText) ?? ""
        var m = EmailParsers.Message(id: stableID(p, body: body), from: p.from, subject: p.subject, body: body, date: date(p.date))
        m.authenticatedDomains = Set(((p.auth?.dkim ?? []) + (p.auth?.dmarc ?? [])).map { $0.lowercased() })
        return m
    }

    /// Same email forwarded twice (or served twice while the server catches
    /// up on a delete) gets the same id, so it's imported once. Hex only: no "-",
    /// because the parsers add "-0", "-1" per record.
    nonisolated static func stableID(_ p: InboxPayload, body: String) -> String {
        let basis = p.messageId.map { "mid:\($0)" } ?? "sum:\(p.from)\n\(p.subject)\n\(p.date)\n\(body.prefix(2000))"
        let digest = SHA256Hex.hash(basis)
        return "fwd" + digest.prefix(32)
    }

    nonisolated static func date(_ text: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: text) ?? ISO8601DateFormatter().date(from: text) ?? .now
    }

    /// Google's request, if it really points at Google's confirm page.
    nonisolated static func gmailRequest(from p: InboxPayload, now: Date = .now) -> GmailForwardingRequest? {
        guard p.kind == InboxPayload.gmailConfirmation,
              EmailParsers.senderDomain(p.from) == "google.com",
              p.from.lowercased().contains("forwarding-noreply@google.com") else { return nil }
        var url: URL?
        if let s = p.confirm?.url, let u = URL(string: s), u.scheme == "https", u.host() == "mail-settings.google.com",
           u.path().hasPrefix("/mail/vf-") {
            url = u
        }
        let code = p.confirm?.code.flatMap { c in c.allSatisfy(\.isNumber) && (6...12).contains(c.count) ? c : nil }
        // Anyone can put forwarding-noreply@google.com in From. Only google.com's
        // own signature makes the link and "from you@gmail.com" trustworthy.
        let verified = (p.auth?.dkim ?? []).contains { EmailParsers.isDomain($0.lowercased(), within: "google.com") }
        if !verified { url = nil }
        guard url != nil || code != nil else { return nil }
        let requestedBy = verified
            ? p.subject.range(of: "Receive Mail from ").map { String(p.subject[$0.upperBound...]).trimmingCharacters(in: .whitespaces) }
            : nil
        return GmailForwardingRequest(code: code, url: url, requestedBy: requestedBy, verified: verified, receivedAt: now)
    }

    /// Reads each email with the same readers as Gmail sync and logs what
    /// they find through `EmailSync` (which goes through `TransactionLogger.log`).
    static func importPayloads(_ payloads: [InboxPayload], in context: ModelContext) async throws -> EmailSync.Summary {
        var records: [EmailRecord] = []
        for p in payloads { records += await GmailSync.read(message(from: p)) }
        return try EmailSync.importRecords(records, in: context, account: account)
    }
}

private nonisolated enum SHA256Hex {
    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

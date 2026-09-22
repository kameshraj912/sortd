import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import Spend

/// The receipt-forwarding inbox: decrypting what the Worker (inbox/) sends,
/// reading it with the existing parsers, and the sync / turn-off flows
/// against a fake server. Fixtures come from inbox/test/fixtures, so the
/// Swift and JavaScript sides are tested against the same bytes.
@MainActor
struct ForwardingInboxTests {
    let context: ModelContext

    init() throws {
        let schema = Schema([Transaction.self, MerchantRule.self, FXRate.self, ImportedRecord.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        context = ModelContext(container)
    }

    var all: [Transaction] { (try? context.fetch(FetchDescriptor<Transaction>())) ?? [] }

    // MARK: Fixtures shared with the Worker's tests

    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    func fixture(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Self.repo.appending(path: "inbox/test/fixtures/\(name)"))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func hex(_ s: String) -> Data {
        var out = Data()
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            out.append(UInt8(s[i..<j], radix: 16)!)
            i = j
        }
        return out
    }

    func payload(from: String = "NAB <alerts@nab.com.au>", subject: String = "Transaction alert",
                 text: String? = "A purchase of $58.30 was made at WOOLWORTHS 3342 on your card ending 1234.",
                 html: String? = nil, dkim: [String] = ["nab.com.au"], auth: Bool = true,
                 messageId: String? = "<alert-58-30@nab.com.au>", kind: String = InboxPayload.mail,
                 confirm: InboxPayload.Confirm? = nil) -> InboxPayload {
        InboxPayload(v: 1, kind: kind, messageId: messageId, from: from, subject: subject,
                     date: "2026-09-20T01:30:00.000Z", text: text, html: html,
                     auth: auth ? .init(dkim: dkim, dmarc: []) : nil, confirm: confirm)
    }

    // MARK: Crypto interop

    @Test func cryptoKitOpensTheOfficialRFC9180Vector() throws {
        let v = try fixture("hpke-rfc9180-p256-sha256-aes256gcm.json")
        let e = try #require(v["encryption"] as? [String: String])
        let sk = try P256.KeyAgreement.PrivateKey(rawRepresentation: hex(v["skRm"] as! String))
        var r = try HPKE.Recipient(privateKey: sk, ciphersuite: .P256_SHA256_AES_GCM_256,
                                   info: hex(v["info"] as! String), encapsulatedKey: hex(v["enc"] as! String))
        let pt = try r.open(hex(e["ct"]!), authenticating: hex(e["aad"]!))
        #expect(pt == hex(e["pt"]!))
    }

    @Test func opensWhatTheWorkerSealedAndLogsThePurchase() async throws {
        let v = try fixture("js-to-swift.json")
        let key = InboxCrypto.Key.software(try P256.KeyAgreement.PrivateKey(rawRepresentation: hex(v["recipientPrivateKeyHex"] as! String)))
        #expect(key.publicKey.base64URL == v["recipientPublicKeyB64u"] as? String)
        let envelope = InboxClient.Envelope(id: v["id"] as! String, enc: v["enc"] as! String, ct: v["ct"] as! String)
        let p = try #require(ForwardingInbox.open(envelope, with: key))
        #expect(p.from == "NAB <alerts@nab.com.au>")
        #expect(p.auth?.dkim == ["nab.com.au"])

        // Moved to another id, it no longer opens.
        let moved = InboxClient.Envelope(id: "mfq2x9a1b-someOtherId00001", enc: envelope.enc, ct: envelope.ct)
        #expect(ForwardingInbox.open(moved, with: key) == nil)
        // Another phone's key can't open it.
        #expect(ForwardingInbox.open(envelope, with: .software(P256.KeyAgreement.PrivateKey())) == nil)

        let s = try await ForwardingInbox.importPayloads([p], in: context)
        #expect(s.added == 1)
        let t = try #require(all.first)
        #expect(t.amount == Decimal(string: "58.30"))
        #expect(t.currencyCode == "AUD")
        #expect(t.source == .email)
        #expect(t.sourceAccount == ForwardingInbox.account)
        #expect(t.rawMerchant.uppercased().contains("WOOLWORTHS"))
    }

    @Test func swiftSealsWhatSwiftOpens() throws {
        let key = InboxCrypto.Key.software(P256.KeyAgreement.PrivateKey())
        #expect(key.publicKey.count == 65 && key.publicKey.first == 0x04)
        let sealed = try InboxCrypto.seal(Data("hello".utf8), to: key.publicKey, aad: Data("id".utf8))
        #expect(try key.open(enc: sealed.enc, ciphertext: sealed.ciphertext, aad: Data("id".utf8)) == Data("hello".utf8))
        #expect(throws: (any Error).self) { try key.open(enc: sealed.enc, ciphertext: sealed.ciphertext, aad: Data("other".utf8)) }
    }

    @Test func keySurvivesTheKeychainForm() throws {
        let key = try InboxCrypto.Key.generate()   // Secure Enclave on a phone, software in the simulator
        let back = try InboxCrypto.Key(stored: key.stored)
        #expect(back.publicKey == key.publicKey)
        let sealed = try InboxCrypto.seal(Data("x".utf8), to: key.publicKey, aad: Data())
        #expect(try back.open(enc: sealed.enc, ciphertext: sealed.ciphertext, aad: Data()) == Data("x".utf8))
        #expect(throws: (any Error).self) { try InboxCrypto.Key(stored: "zz:AAAA") }
    }

    // MARK: Reading what arrives

    @Test func aForgedBankAlertIsNotLogged() async throws {
        // Says it's from NAB, but nothing proved it: no DKIM for nab.com.au.
        let unsigned = payload(dkim: [])
        #expect(ForwardingInbox.message(from: unsigned).authenticatedDomains == [])
        // Signed, but by someone else's domain.
        let otherDomain = payload(dkim: ["evil.example"], messageId: "<2@x>")
        // No auth block at all must still mean "nothing proven", never "can't tell".
        let noAuth = payload(auth: false, messageId: "<3@x>")
        #expect(ForwardingInbox.message(from: noAuth).authenticatedDomains == [])
        let s = try await ForwardingInbox.importPayloads([unsigned, otherDomain, noAuth], in: context)
        #expect(s.added == 0)
        #expect(all.isEmpty)
    }

    @Test func aDMARCProvenDomainCountsToo() {
        var p = payload(dkim: [])
        p.auth?.dmarc = ["NAB.com.au"]
        #expect(ForwardingInbox.message(from: p).authenticatedDomains == ["nab.com.au"])
    }

    @Test func anyShopsReceiptGoesToTheGeneralReader() async throws {
        let p = payload(from: "Corner Books <orders@cornerbooks.example>", subject: "Your receipt",
                        text: "Thanks for your order.\nTotal: $12.50\n", dkim: [], messageId: "<r1@cornerbooks.example>")
        let s = try await ForwardingInbox.importPayloads([p], in: context)
        #expect(s.added == 1)
        #expect(all.first?.amount == Decimal(string: "12.50"))
    }

    @Test func anHTMLOnlyEmailIsTurnedIntoText() async throws {
        let p = payload(text: nil, html: "<p>A purchase of <b>$58.30</b> was made at WOOLWORTHS 3342 on your card ending 1234.</p>")
        #expect(ForwardingInbox.message(from: p).body.contains("$58.30"))
        #expect(!ForwardingInbox.message(from: p).body.contains("<b>"))
        let s = try await ForwardingInbox.importPayloads([p], in: context)
        #expect(s.added == 1)
    }

    @Test func theSameEmailTwiceIsLoggedOnce() async throws {
        let p = payload()
        try await ForwardingInbox.importPayloads([p], in: context)
        let again = try await ForwardingInbox.importPayloads([p], in: context)
        #expect(again.added == 0)
        #expect(all.count == 1)
        // Without a Message-ID the id comes from the content, and is still stable.
        let a = ForwardingInbox.message(from: payload(messageId: nil)).id
        #expect(a == ForwardingInbox.message(from: payload(messageId: nil)).id)
        #expect(a.hasPrefix("fwd") && !a.contains("-"))
    }

    @Test func googlesConfirmationIsShownOnlyWhenItsReallyGoogles() {
        let good = payload(from: "Gmail Team <forwarding-noreply@google.com>",
                           subject: "(#123456789) Gmail Forwarding Confirmation - Receive Mail from raj@gmail.com",
                           kind: InboxPayload.gmailConfirmation,
                           confirm: .init(code: "123456789", url: "https://mail-settings.google.com/mail/vf-%5Babc%5D-xyz"))
        let r = ForwardingInbox.gmailRequest(from: good)
        #expect(r?.code == "123456789")
        #expect(r?.url?.host() == "mail-settings.google.com")
        #expect(r?.requestedBy == "raj@gmail.com")

        var phish = good
        phish.confirm?.url = "https://mail-settings.google.com.evil.example/mail/vf-x"
        #expect(ForwardingInbox.gmailRequest(from: phish)?.url == nil)   // the code still shows; the link doesn't
        phish.confirm?.url = "http://mail-settings.google.com/mail/vf-x"
        #expect(ForwardingInbox.gmailRequest(from: phish)?.url == nil)
        var notGoogle = good
        notGoogle.from = "Gmail Team <forwarding-noreply@google.com.evil.example>"
        #expect(ForwardingInbox.gmailRequest(from: notGoogle) == nil)
        var notAConfirmation = good
        notAConfirmation.kind = InboxPayload.mail
        #expect(ForwardingInbox.gmailRequest(from: notAConfirmation) == nil)
    }

    // MARK: The whole flow, against a fake server

    @Test func turnOnSyncAndTurnOff() async throws {
        let server = FakeInboxServer()
        let defaults = try #require(UserDefaults(suiteName: "ForwardingInboxTests-\(UUID().uuidString)"))
        let inbox = ForwardingInbox(client: server.client, secrets: .memory(), defaults: defaults)
        #expect(!inbox.isOn)

        let address = try await inbox.turnOn()
        #expect(address == server.address)
        #expect(inbox.isOn)
        let pk = try #require(server.publicKey)
        #expect(inbox.setupURL?.absoluteString == "https://inbox.test/setup#a=\(address)")
        #expect(inbox.setupURL?.query == nil)   // the address never goes in the query

        // What the Worker would store: an alert, Google's confirmation, and junk.
        let alert = try JSONEncoder().encode(payload())
        let confirm = try JSONEncoder().encode(payload(
            from: "Gmail Team <forwarding-noreply@google.com>",
            subject: "(#123456789) Gmail Forwarding Confirmation - Receive Mail from raj@gmail.com",
            text: "Confirmation code: 123456789", messageId: "<c@google.com>", kind: InboxPayload.gmailConfirmation,
            confirm: .init(code: "123456789", url: "https://mail-settings.google.com/mail/vf-abc")))
        try server.store(alert, id: "000000001-aaaaaaaaaaaaaaaa", to: pk)
        try server.store(confirm, id: "000000002-bbbbbbbbbbbbbbbb", to: pk)
        server.storeJunk(id: "000000003-cccccccccccccccc")

        let s = try await inbox.sync(in: context)
        #expect(s.added == 1)
        #expect(all.count == 1)
        #expect(inbox.gmailRequest?.code == "123456789")
        // Read ones are deleted from the server; the one that can't be opened is left to expire.
        #expect(server.deleted.sorted() == ["000000001-aaaaaaaaaaaaaaaa", "000000002-bbbbbbbbbbbbbbbb"])
        #expect(server.waiting == ["000000003-cccccccccccccccc"])
        #expect(inbox.lastResult?.contains("1 couldn't be opened") == true)
        #expect(server.lastAuthorization == "Bearer \(address.split(separator: "@")[0]).\(server.token)")

        await inbox.turnOff(deletePurchases: true, in: context)
        #expect(server.turnedOff)
        #expect(!inbox.isOn)
        #expect(inbox.address == nil)
        #expect(inbox.gmailRequest == nil)
        #expect(all.isEmpty)   // "Turn Off and Delete Its Purchases"
    }

    @Test func aTurnOffWhileOfflineIsSentLater() async throws {
        let server = FakeInboxServer()
        let secrets = InboxSecrets.memory()
        let defaults = try #require(UserDefaults(suiteName: "ForwardingInboxTests-\(UUID().uuidString)"))
        let inbox = ForwardingInbox(client: server.client, secrets: secrets, defaults: defaults)
        try await inbox.turnOn()
        server.offline = true
        await inbox.turnOff(deletePurchases: false, in: nil)
        #expect(!inbox.isOn)
        #expect(!server.turnedOff)
        server.offline = false
        await inbox.retryPendingTurnOff()
        #expect(server.turnedOff)
    }

    @Test func pagesThroughEverythingWaiting() async throws {
        let server = FakeInboxServer()
        server.pageSize = 2
        let defaults = try #require(UserDefaults(suiteName: "ForwardingInboxTests-\(UUID().uuidString)"))
        let inbox = ForwardingInbox(client: server.client, secrets: .memory(), defaults: defaults)
        try await inbox.turnOn()
        let pk = try #require(server.publicKey)
        for i in 1...5 {
            let p = payload(text: "A purchase of $\(i).00 was made at SHOP \(i) on your card ending 1234.", messageId: "<\(i)@nab.com.au>")
            try server.store(try JSONEncoder().encode(p), id: "00000000\(i)-aaaaaaaaaaaaaaaa", to: pk)
        }
        let s = try await inbox.sync(in: context)
        #expect(s.added == 5)
        #expect(server.waiting.isEmpty)
    }

    // MARK: The setup page asks Gmail for every sender the app reads

    @Test func setupPageFilterCoversEveryBankAndReceiptSender() throws {
        let js = try String(contentsOf: Self.repo.appending(path: "inbox/src/filters.js"), encoding: .utf8)
        for bank in BankAlerts.known {
            #expect(js.contains("\"\(bank.domain)\""), "inbox/src/filters.js is missing \(bank.domain)")
        }
        for domain in EmailParsers.ruleDomains {
            #expect(js.contains("\(domain)\""), "inbox/src/filters.js is missing \(domain)")
        }
    }
}

/// Stands in for the Worker: register, list (paged), delete, turn off. Seals
/// with CryptoKit the way the Worker does, so the phone side is exercised end to end.
nonisolated final class FakeInboxServer: @unchecked Sendable {
    let address = "abcdefghijkmnpqrstuvwxyz@in.sortd.page"
    let token = String(repeating: "t", count: 43)
    private let lock = NSLock()
    private var messages: [(id: String, enc: String, ct: String)] = []
    private(set) var publicKey: Data?
    private(set) var deleted: [String] = []
    private(set) var turnedOff = false
    private(set) var lastAuthorization: String?
    var offline = false
    var pageSize = 20

    var waiting: [String] { lock.withLock { messages.map(\.id) } }

    func store(_ plaintext: Data, id: String, to publicKey: Data) throws {
        let sealed = try InboxCrypto.seal(plaintext, to: publicKey, aad: Data(id.utf8))
        lock.withLock { messages.append((id, sealed.enc.base64URL, sealed.ciphertext.base64URL)) }
    }

    func storeJunk(id: String) {
        lock.withLock { messages.append((id, Data(repeating: 4, count: 65).base64URL, Data(repeating: 1, count: 40).base64URL)) }
    }

    var client: InboxClient {
        InboxClient(base: URL(string: "https://inbox.test")!) { [self] req in try self.handle(req) }
    }

    private func respond(_ req: URLRequest, _ status: Int, _ body: Any? = nil) throws -> (Data, URLResponse) {
        let data = try body.map { try JSONSerialization.data(withJSONObject: $0) } ?? Data()
        return (data, HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    private func handle(_ req: URLRequest) throws -> (Data, URLResponse) {
        if offline { throw URLError(.notConnectedToInternet) }
        let path = req.url!.path()
        let method = req.httpMethod ?? "GET"
        if path == "/api/inbox/register", method == "POST" {
            let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: String]
            guard body?["suite"] == "P256_SHA256_AES_GCM_256", let pk = body?["publicKey"].flatMap({ Data(base64URL: $0) }) else {
                return try respond(req, 400)
            }
            lock.withLock { publicKey = pk }
            return try respond(req, 201, ["ok": true, "address": address, "token": token])
        }
        let auth = req.value(forHTTPHeaderField: "Authorization")
        lock.withLock { lastAuthorization = auth }
        guard auth == "Bearer abcdefghijkmnpqrstuvwxyz.\(token)", !turnedOff else { return try respond(req, 401) }
        if path == "/api/inbox/messages", method == "GET" {
            return try lock.withLock {
                // Like KV: the cursor is a position in key order, so deletes don't shift it.
                let after = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "cursor" }?.value ?? ""
                let rest = messages.sorted { $0.id < $1.id }.filter { $0.id > after }
                let page = rest.prefix(pageSize)
                let more = rest.count > page.count
                return try respond(req, 200, ["ok": true, "more": more, "cursor": more ? (page.last?.id ?? "") as Any : NSNull(),
                                              "messages": page.map { ["id": $0.id, "enc": $0.enc, "ct": $0.ct] }])
            }
        }
        if path.hasPrefix("/api/inbox/messages/"), method == "DELETE" {
            let id = String(path.dropFirst("/api/inbox/messages/".count))
            lock.withLock {
                deleted.append(id)
                messages.removeAll { $0.id == id }
            }
            return try respond(req, 204)
        }
        if path == "/api/inbox", method == "DELETE" {
            lock.withLock { turnedOff = true; messages = [] }
            return try respond(req, 204)
        }
        return try respond(req, 404)
    }
}

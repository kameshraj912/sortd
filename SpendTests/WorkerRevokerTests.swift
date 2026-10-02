import Testing
import Foundation
import CryptoKit
@testable import Spend

/// Records every request and answers from a script of (status, body).
private final class TransportFake {
    var requests: [URLRequest] = []
    var script: [(Int, String)]
    var fails = false
    init(_ script: [(Int, String)]) { self.script = script }

    func call(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if fails { throw URLError(.notConnectedToInternet) }
        let (status, body) = script.isEmpty ? (500, "") : script.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

private final class AttesterFake: AppAttester {
    var isSupported = true
    var hashes: [Data] = []
    func attest(clientDataHash: Data) async throws -> (keyID: String, attestation: Data) {
        hashes.append(clientDataHash)
        return ("key-1", Data("att".utf8))
    }
}

private final class RevokeCounter {
    var googleRevokes = 0
    var appleCodes = 0
}

/// `WorkerRevoker` against the account Worker spec
/// (docs/specs/2026-09-25-account-worker.md): challenge, App Attest
/// headers, the two action routes, and which failures are retried.
@MainActor
struct WorkerRevokerTests {
    static let url = URL(string: "https://account.example")!
    static let hash = String(repeating: "ab", count: 32)
    static let apple = Account(provider: .apple, subject: "001234.abcdef", email: "raj@example.com")
    static let google = Account(provider: .google, subject: "10769150350006150715113082367", email: "raj@example.org")

    private func revoker(url: URL? = WorkerRevokerTests.url, transport: TransportFake,
                         attester: AttesterFake? = nil, counter: RevokeCounter? = nil,
                         appleCode: Result<String, AccountError> = .success("code-1"),
                         appleUser: String = WorkerRevokerTests.apple.subject) -> WorkerRevoker {
        let attester = attester ?? AttesterFake()
        let counter = counter ?? RevokeCounter()
        return WorkerRevoker(url: url, deps: WorkerRevoker.Dependencies(
            transport: { try await transport.call($0) },
            attester: attester,
            appleCode: { _ in
                counter.appleCodes += 1
                return WorkerRevoker.AppleCode(user: appleUser, code: try appleCode.get())
            },
            googleRevoke: { counter.googleRevokes += 1 },
            clientID: "com.kameshraj.spend"))
    }

    private func json(_ request: URLRequest) -> [String: String] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]) ?? [:]
    }

    private func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: delete-person

    @Test func deletePersonAsksForAChallengeThenPostsWithAttestHeaders() async throws {
        let transport = TransportFake([(200, #"{"challenge":"chal-1"}"#), (204, "")])
        let attester = AttesterFake()
        let r = revoker(transport: transport, attester: attester)

        try await r.deletePerson(hash: Self.hash)

        #expect(transport.requests.count == 2)
        let challenge = transport.requests[0]
        #expect(challenge.url?.path == "/v1/challenge")
        #expect(challenge.httpMethod == "POST")
        let action = transport.requests[1]
        #expect(action.url?.path == "/v1/posthog/delete-person")
        #expect(json(action) == ["distinct_id": Self.hash])
        // The challenge is bound to the exact bytes the action sends.
        #expect(json(challenge) == ["route": "posthog/delete-person", "body_sha256": hex(action.httpBody ?? Data())])
        #expect(action.value(forHTTPHeaderField: "X-Attest-Key-Id") == "key-1")
        #expect(action.value(forHTTPHeaderField: "X-Attest-Object") == Data("att".utf8).base64EncodedString())
        #expect(action.value(forHTTPHeaderField: "X-Attest-Challenge") == "chal-1")
        #expect(attester.hashes == [Data(SHA256.hash(data: Data("chal-1".utf8)))])
        // No CORS, nothing but JSON.
        #expect(action.value(forHTTPHeaderField: "Origin") == nil)
        #expect(action.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func noWorkerURLIsOfflineAndSendsNothing() async {
        let transport = TransportFake([])
        let r = revoker(url: nil, transport: transport)

        await #expect(throws: AccountError.offline) { try await r.deletePerson(hash: Self.hash) }

        #expect(transport.requests.isEmpty)
    }

    @Test func a502IsRejectedForGoodNotRetried() async {
        let transport = TransportFake([(200, #"{"challenge":"c"}"#), (502, #"{"error":"posthog_auth"}"#)])
        let r = revoker(transport: transport)

        await #expect(throws: AccountError.rejected("posthog_auth")) { try await r.deletePerson(hash: Self.hash) }
    }

    @Test func a503IsOfflineSoTheStoreRetries() async {
        let transport = TransportFake([(200, #"{"challenge":"c"}"#), (503, #"{"error":"posthog_unavailable"}"#)])
        let r = revoker(transport: transport)

        await #expect(throws: AccountError.offline) { try await r.deletePerson(hash: Self.hash) }
    }

    @Test func aNetworkErrorIsOffline() async {
        let transport = TransportFake([])
        transport.fails = true
        let r = revoker(transport: transport)

        await #expect(throws: AccountError.offline) { try await r.deletePerson(hash: Self.hash) }
    }

    @Test func aChallengeWithoutAChallengeIsOffline() async {
        let transport = TransportFake([(200, "{}")])
        let r = revoker(transport: transport)

        await #expect(throws: AccountError.offline) { try await r.deletePerson(hash: Self.hash) }
        #expect(transport.requests.count == 1)
    }

    @Test func noAppAttestOnThisDeviceIsNotSupportedAndSendsNothing() async {
        let transport = TransportFake([(200, #"{"challenge":"c"}"#)])
        let attester = AttesterFake()
        attester.isSupported = false
        let r = revoker(transport: transport, attester: attester)

        await #expect(throws: AccountError.notSupported) { try await r.deletePerson(hash: Self.hash) }
        #expect(transport.requests.isEmpty)
    }

    // MARK: Apple revoke

    @Test func appleRevokeGetsAFreshCodeAndPostsItWithTheClientID() async throws {
        let transport = TransportFake([(200, #"{"challenge":"c"}"#), (204, "")])
        let counter = RevokeCounter()
        let r = revoker(transport: transport, counter: counter)

        try await r.revoke(Self.apple)

        #expect(counter.appleCodes == 1)
        #expect(transport.requests[1].url?.path == "/v1/apple/revoke")
        #expect(json(transport.requests[1]) == ["client_id": "com.kameshraj.spend", "authorization_code": "code-1"])
        #expect(json(transport.requests[0])["route"] == "apple/revoke")
    }

    @Test func cancellingTheAppleSheetIsCancelledAndSendsNothing() async {
        let transport = TransportFake([])
        let r = revoker(transport: transport, appleCode: .failure(.cancelled))

        await #expect(throws: AccountError.cancelled) { try await r.revoke(Self.apple) }
        #expect(transport.requests.isEmpty)
    }

    @Test func aDifferentAppleAccountIsRejectedAndSendsNothing() async {
        let transport = TransportFake([])
        let r = revoker(transport: transport, appleUser: "999.other")

        await #expect(throws: AccountError.rejected(WorkerRevoker.wrongAppleAccount)) { try await r.revoke(Self.apple) }
        #expect(transport.requests.isEmpty)
    }

    @Test func anAppleRevokeThatCannotBeSentIsNeverQueuedSinceTheCodeExpires() async {
        let transport = TransportFake([])
        transport.fails = true
        let r = revoker(transport: transport)

        await #expect(throws: AccountError.rejected(WorkerRevoker.appleManualSteps)) { try await r.revoke(Self.apple) }
    }

    @Test func aQueuedAppleRevokeIsRejectedItNeedsAFreshCode() async {
        let r = revoker(transport: TransportFake([]))

        await #expect(throws: AccountError.rejected(WorkerRevoker.appleManualSteps)) {
            try await r.revoke(queued: .apple, subjectHash: "x")
        }
    }

    // MARK: Google revoke

    @Test func googleRevokeCancelsTheGrant() async throws {
        let counter = RevokeCounter()
        let r = revoker(transport: TransportFake([]), counter: counter)

        try await r.revoke(Self.google)

        #expect(counter.googleRevokes == 1)
    }
}

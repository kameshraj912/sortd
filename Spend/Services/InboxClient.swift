import Foundation

/// Talks to the forwarding inbox Worker (inbox/ in this repo) at inbox.sortd.page.
/// Everything it downloads is ciphertext; `InboxCrypto` opens it on the phone.
nonisolated struct InboxClient: Sendable {
    var base: URL
    /// Swappable so tests can stand in for the server.
    var transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let live = InboxClient(base: URL(string: "https://inbox.sortd.page")!) { request in
        try await session.data(for: request)
    }

    /// No cookies, no cache: nothing about the inbox is kept on disk by URLSession.
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.timeoutIntervalForRequest = 30
        return URLSession(configuration: c)
    }()

    struct Credentials: Codable, Equatable, Sendable {
        var address: String
        var token: String
        /// "Bearer <mailbox>.<token>"
        var header: String { "Bearer \(address.split(separator: "@").first ?? "").\(token)" }
    }

    struct Registration: Decodable, Sendable {
        let address: String
        let token: String
    }

    struct Envelope: Decodable, Equatable, Sendable {
        let id: String
        let enc: String
        let ct: String
    }

    struct Page: Decodable, Sendable {
        let messages: [Envelope]
        let more: Bool
        let cursor: String?
    }

    struct Failure: LocalizedError, Equatable {
        let status: Int
        var errorDescription: String? {
            switch status {
            case 401: "This forwarding address was turned off. Get a new one."
            case 429: "Too many tries. Wait a minute and try again."
            case 0: "Couldn't reach Sortd's inbox. Check your connection."
            default: "Sortd's inbox answered with an error (\(status))."
            }
        }
    }

    func register(publicKey: Data) async throws -> Registration {
        let body = try JSONSerialization.data(withJSONObject: ["publicKey": publicKey.base64URL, "suite": InboxCrypto.suiteName])
        return try JSONDecoder().decode(Registration.self, from: await send("POST", "api/inbox/register", body: body, expect: 201))
    }

    func list(_ c: Credentials, cursor: String? = nil) async throws -> Page {
        var path = "api/inbox/messages"
        if let cursor, let q = cursor.addingPercentEncoding(withAllowedCharacters: .alphanumerics) { path += "?cursor=\(q)" }
        return try JSONDecoder().decode(Page.self, from: await send("GET", path, auth: c))
    }

    func delete(_ id: String, _ c: Credentials) async throws {
        guard id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { throw Failure(status: 400) }
        _ = try await send("DELETE", "api/inbox/messages/\(id)", auth: c, expect: 204)
    }

    /// Deletes the mailbox and everything waiting in it. Mail to the old address bounces within about a minute.
    func turnOff(_ c: Credentials) async throws {
        _ = try await send("DELETE", "api/inbox", auth: c, expect: 204)
    }

    private func send(_ method: String, _ path: String, body: Data? = nil, auth: Credentials? = nil, expect: Int = 200) async throws -> Data {
        guard let url = URL(string: path, relativeTo: base) else { throw Failure(status: 400) }
        var req = URLRequest(url: url.absoluteURL)
        req.httpMethod = method
        req.httpBody = body
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let auth { req.setValue(auth.header, forHTTPHeaderField: "Authorization") }
        let data: Data, response: URLResponse
        do { (data, response) = try await transport(req) } catch { throw Failure(status: 0) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == expect else { throw Failure(status: status) }
        return data
    }
}

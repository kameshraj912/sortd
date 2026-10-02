import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// "Continue with Google" without a Google SDK: Apple's secure sign-in sheet
/// (ASWebAuthenticationSession) plus OAuth 2.0 with PKCE, as Google
/// recommends for installed apps. Identity only: `openid` and `email`, no
/// other scope. The token kept in the Keychain exists only so Delete Account
/// can cancel the grant.
@MainActor
final class GoogleAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    /// iOS OAuth client in the "Sortd" Google Cloud project. Public by design
    /// (every iOS app ships its client ID); it is not a secret.
    nonisolated static let clientID = "36410288175-4hr5juudo6umb5pcv925t4rocn2riug7.apps.googleusercontent.com"
    /// Exactly what the sign-in asks for: who the person is, nothing else.
    static let scopes = ["openid", "email"]

    /// The reversed client ID, which Google accepts as a redirect for iOS clients.
    static var redirectScheme: String {
        "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }
    static var redirectURI: String { redirectScheme + ":/oauth2redirect" }

    enum AuthError: LocalizedError, Equatable {
        case cancelled, noCode, providerFailed, server(String)
        var errorDescription: String? {
            switch self {
            case .cancelled: "Sign-in was cancelled."
            case .noCode: "Google didn't finish signing in. Please try again."
            case .providerFailed: "Google's answer didn't check out. Please try again."
            case .server(let text): text
            }
        }
    }

    struct Tokens: Decodable {
        let access_token: String
        let expires_in: Int
        let refresh_token: String?
        let id_token: String?
        let scope: String?
    }

    private var session: ASWebAuthenticationSession?

    /// The secure web sign-in sheet as one step: opens `url` and returns
    /// the redirect that comes back on `scheme`. Tests swap in a fake.
    typealias WebSession = @MainActor (_ url: URL, _ scheme: String) async throws -> URL
    private let webSession: WebSession?
    /// Holds the privacy cover off while the sheet is up (see `SystemPrompt`).
    private let prompt: SystemPrompt

    /// `prompt` nil means the app's shared one (resolved here, on the main
    /// actor, since a default argument is evaluated outside it).
    init(webSession: WebSession? = nil, prompt: SystemPrompt? = nil) {
        self.webSession = webSession
        self.prompt = prompt ?? .shared
        super.init()
    }

    /// Sign in with Google as an identity (sub-spec 4): asks for exactly
    /// `scopes` and returns the ID token's stable `sub` and email.
    /// The token comes straight from Google's token endpoint over TLS, so
    /// its claims are read without signature checks (Google's own rule for
    /// tokens "that came directly from Google"); a server that ever uses
    /// this ID must verify the token against Google's keys. The token is
    /// kept in the Keychain only so Delete Account can cancel the grant.
    func signInForIdentity() async throws -> Account {
        let (code, verifier) = try await authorize(scopes: Self.scopes)
        let tokens = try await Self.exchange(code: code, verifier: verifier)
        guard let idToken = tokens.id_token else { throw AuthError.providerFailed }
        let account = try Self.identity(fromIDToken: idToken)
        Keychain.set(tokens.refresh_token ?? tokens.access_token, for: Self.identityTokenKey)
        return account
    }

    /// The account in an ID token, after the checks that need no key: it
    /// was minted for our client (`aud`), by Google (`iss`), and has not
    /// expired. Anything else is `providerFailed`.
    nonisolated static func identity(fromIDToken token: String, clientID: String = clientID, now: Date = .now) throws -> Account {
        guard let claims = claims(fromIDToken: token) else { throw AuthError.providerFailed }
        let audience: [String] = (claims["aud"] as? [String]) ?? (claims["aud"] as? String).map { [$0] } ?? []
        guard audience.contains(clientID) else { throw AuthError.providerFailed }
        guard let issuer = claims["iss"] as? String, ["https://accounts.google.com", "accounts.google.com"].contains(issuer) else {
            throw AuthError.providerFailed
        }
        guard let exp = claims["exp"] as? Double, exp > now.timeIntervalSince1970 else { throw AuthError.providerFailed }
        guard let sub = claims["sub"] as? String, !sub.isEmpty else { throw AuthError.providerFailed }
        return Account(provider: .google, subject: sub, email: claims["email"] as? String)
    }

    /// Delete Account: cancels the identity grant with Google and forgets
    /// the token. A failed revoke joins the pending list and is retried.
    static func revokeIdentity() async {
        guard let token = Keychain.get(identityTokenKey) else { return }
        Keychain.delete(identityTokenKey)
        await revoke(token)
    }

    private static let identityTokenKey = "google-identity-token"

    /// Google's sheet for `scopes`; returns the authorization code and the
    /// PKCE verifier that goes with it. The sheet makes the scene inactive,
    /// so the whole of it runs under `SystemPrompt`: a privacy cover on top
    /// of the sheet would end the sign-in as cancelled after a second.
    func authorize(scopes: [String]) async throws -> (code: String, verifier: String) {
        let verifier = Self.randomString(64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = Self.randomString(24)
        var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        url.queryItems = [
            .init(name: "client_id", value: Self.clientID),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "prompt", value: "consent select_account"),
        ]

        let callback: URL = try await prompt.showing {
            if let webSession { return try await webSession(url.url!, Self.redirectScheme) }
            return try await openSheet(url.url!)
        }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw AuthError.noCode
        }
        return (code, verifier)
    }

    /// The real sheet: `ASWebAuthenticationSession`, which returns the
    /// redirect URL, or `cancelled` when the person closes it.
    private func openSheet(_ url: URL) async throws -> URL {
        let sheet = Perf.begin("auth.googleSheet")
        return try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url, callback: .customScheme(Self.redirectScheme)) { url, error in
                sheet.end(url == nil ? "closed" : "")
                if let url { cont.resume(returning: url) }
                else if let e = error as? ASWebAuthenticationSessionError, e.code == .canceledLogin { cont.resume(throwing: AuthError.cancelled) }
                else { cont.resume(throwing: error ?? AuthError.noCode) }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = false
            session = s
            if !s.start() { cont.resume(throwing: AuthError.noCode) }
        }
    }

    private static func exchange(code: String, verifier: String) async throws -> Tokens {
        try await tokenRequest([
            "grant_type": "authorization_code", "code": code, "client_id": Self.clientID,
            "redirect_uri": Self.redirectURI, "code_verifier": verifier,
        ])
    }

    /// Google-bound requests only: nothing cached to disk, no cookies kept.
    nonisolated static let session = URLSession(configuration: .ephemeral)

    /// Tokens whose revoke hasn't reached Google yet (offline, app killed).
    /// Kept only until Google confirms, then deleted.
    private static let pendingKey = "google-revoke-pending"

    private static func revoke(_ token: String) async {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form(["token": token])
        let code = ((try? await session.data(for: req))?.1 as? HTTPURLResponse)?.statusCode
        // 200 = revoked. 400 = Google no longer knows the token (already gone).
        if code == 200 || code == 400 { return }
        var pending = Set((Keychain.get(pendingKey) ?? "").split(separator: "\n").map(String.init))
        pending.insert(token)
        Keychain.set(pending.joined(separator: "\n"), for: pendingKey)
    }

    /// For Delete All. Reads the saved list of revokes that never reached
    /// Google, so the Keychain can be wiped straight away, then asks Google
    /// again for each one. (The wipe would otherwise lose that list and leave
    /// the grant switched on.)
    static func revokePending() {
        let tokens = pendingTokens(Keychain.get(pendingKey))
        Task { for token in tokens { await revoke(token) } }
    }

    /// The saved list of failed revokes (one token per line), each once.
    static func pendingTokens(_ saved: String?) -> [String] {
        var seen = Set<String>()
        return (saved ?? "").split(separator: "\n").map(String.init).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The one-time clean-up after Gmail was removed: asks Google to cancel
    /// each old Gmail grant. A revoke that fails joins the pending list.
    static func revokeLegacy(_ tokens: [String]) async {
        for token in tokens { await revoke(token) }
    }

    /// Tries the revokes that failed before. Called when the app becomes active.
    static func retryPendingRevokes() async {
        guard let saved = Keychain.get(pendingKey), !saved.isEmpty else { return }
        Keychain.delete(pendingKey)
        for token in saved.split(separator: "\n") { await revoke(String(token)) }
    }

    private static func tokenRequest(_ fields: [String: String]) async throws -> Tokens {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form(fields)
        req.timeoutInterval = 20
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            // Google's error JSON, e.g. {"error":"invalid_grant"} when access was revoked.
            let text = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw AuthError.server(text == "invalid_grant"
                                   ? "Google access has ended. Please sign in again."
                                   : "Google sign-in failed (\(text ?? "unknown error")).")
        }
        return try JSONDecoder().decode(Tokens.self, from: data)
    }

    private static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=/:")
        return Data(fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&").utf8)
    }

    /// The ID token's payload, decoded and not verified: only for a token
    /// that came straight from Google's token endpoint (see `signInForIdentity`).
    nonisolated static func claims(fromIDToken token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2, let data = Data(base64URL: String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json
    }

    private static func randomString(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars[Int(rng.next() % UInt64(chars.count))] })
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.compactMap(\.keyWindow).first { return window }
            // A sign-in can only start from an open window, so a scene exists.
            return ASPresentationAnchor(windowScene: scenes[0])
        }
    }
}

nonisolated extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URL s: String) {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        self.init(base64Encoded: b)
    }
}

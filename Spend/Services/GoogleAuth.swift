import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// "Connect with Google" without a Google SDK: Apple's secure sign-in sheet
/// (ASWebAuthenticationSession) plus OAuth 2.0 with PKCE, as Google
/// recommends for installed apps. Only read-only Gmail access is requested.
/// The refresh token goes in the Keychain; access tokens live in memory.
@MainActor
final class GoogleAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    /// iOS OAuth client in the "Sortd" Google Cloud project. Public by design
    /// (every iOS app ships its client ID); it is not a secret.
    static let clientID = "36410288175-4hr5juudo6umb5pcv925t4rocn2riug7.apps.googleusercontent.com"
    static let scopes = ["openid", "email", "https://www.googleapis.com/auth/gmail.readonly"]
    /// Sign in with Google as an identity only (AccountStore): who the user
    /// is, nothing from Gmail. Never the readonly scope, so the identity
    /// request cannot widen what the Gmail review looks at.
    static let identityScopes = ["openid", "email"]

    /// The reversed client ID, which Google accepts as a redirect for iOS clients.
    static var redirectScheme: String {
        "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }
    static var redirectURI: String { redirectScheme + ":/oauth2redirect" }

    enum AuthError: LocalizedError {
        case cancelled, noCode, noRefreshToken, missingGmailAccess, server(String)
        var errorDescription: String? {
            switch self {
            case .cancelled: "Sign-in was cancelled."
            case .noCode: "Google didn't finish signing in. Please try again."
            case .noRefreshToken: "Google didn't allow ongoing access. Please try again."
            case .missingGmailAccess: "Sortd needs permission to read receipts. Please tick the Gmail box when Google asks."
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

    /// Opens Google's sign-in page. Returns the account's email and saves the
    /// refresh token in the Keychain under that email. `onAuthorized` runs
    /// when Google's page closes with a yes, before the token exchange.
    func signIn(onAuthorized: () -> Void = {}) async throws -> String {
        let (code, verifier) = try await authorize(scopes: Self.scopes)
        onAuthorized()

        let exchange = Perf.begin("auth.tokenExchange")
        defer { exchange.end() }
        let tokens = try await Self.exchange(code: code, verifier: verifier)
        guard let refresh = tokens.refresh_token else { throw AuthError.noRefreshToken }
        guard (tokens.scope ?? "").contains("gmail.readonly") else {
            await Self.revoke(refresh)
            throw AuthError.missingGmailAccess
        }
        let email = tokens.id_token.flatMap(Self.email(fromIDToken:)) ?? "Gmail"
        Keychain.set(refresh, for: Self.keychainKey(email))
        Self.cache[email] = (tokens.access_token, Date.now.addingTimeInterval(Double(tokens.expires_in) - 60))
        return email
    }

    /// Sign in with Google as an identity (sub-spec 4): asks for exactly
    /// `identityScopes` and returns the ID token's stable `sub` and email.
    /// The token comes straight from Google's token endpoint over TLS, so
    /// its claims are read without signature checks (Google's own rule for
    /// tokens "that came directly from Google"); a server that ever uses
    /// this ID must verify the token against Google's keys. The token is
    /// kept in the Keychain only so Delete Account can cancel the grant.
    func signInForIdentity() async throws -> Account {
        let (code, verifier) = try await authorize(scopes: Self.identityScopes)
        let tokens = try await Self.exchange(code: code, verifier: verifier)
        guard let idToken = tokens.id_token, let claims = Self.claims(fromIDToken: idToken),
              let sub = claims["sub"] as? String, !sub.isEmpty else { throw AuthError.noCode }
        Keychain.set(tokens.refresh_token ?? tokens.access_token, for: Self.identityTokenKey)
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
    /// PKCE verifier that goes with it.
    private func authorize(scopes: [String]) async throws -> (code: String, verifier: String) {
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

        let sheet = Perf.begin("auth.googleSheet")
        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: url.url!, callback: .customScheme(Self.redirectScheme)) { url, error in
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
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            throw AuthError.noCode
        }
        return (code, verifier)
    }

    private static func exchange(code: String, verifier: String) async throws -> Tokens {
        try await tokenRequest([
            "grant_type": "authorization_code", "code": code, "client_id": Self.clientID,
            "redirect_uri": Self.redirectURI, "code_verifier": verifier,
        ])
    }

    // MARK: Tokens

    private static var cache: [String: (token: String, expires: Date)] = [:]

    static func keychainKey(_ email: String) -> String { "google-refresh-\(email)" }

    /// A valid access token for this account, refreshing it when needed.
    static func accessToken(for email: String) async throws -> String {
        if let c = cache[email], c.expires > .now { return c.token }
        guard let refresh = Keychain.get(keychainKey(email)) else { throw AuthError.noRefreshToken }
        let t = try await tokenRequest(["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientID])
        cache[email] = (t.access_token, Date.now.addingTimeInterval(Double(t.expires_in) - 60))
        return t.access_token
    }

    /// Tells Google to cancel Sortd's access, and forgets the token here.
    static func disconnect(_ email: String) async {
        if let refresh = Keychain.get(keychainKey(email)) { await revoke(refresh) }
        Keychain.delete(keychainKey(email))
        cache[email] = nil
    }

    /// For Delete All. Reads every saved token first, so the Keychain can be
    /// wiped straight away, then asks Google to cancel each one. (Revoking
    /// after the wipe found no token and left Google access switched on.)
    /// Includes tokens from an earlier disconnect whose revoke never reached
    /// Google: that list lives in the Keychain too, so the wipe would lose it.
    static func revokeAll(_ emails: [String]) {
        let tokens = tokensToRevoke(accounts: emails.compactMap { Keychain.get(keychainKey($0)) },
                                    pending: Keychain.get(pendingKey))
        cache = [:]
        Task { for token in tokens { await revoke(token) } }
    }

    /// The connected accounts' tokens plus the saved list of failed revokes
    /// (one per line), each once.
    static func tokensToRevoke(accounts: [String], pending: String?) -> [String] {
        let saved = (pending ?? "").split(separator: "\n").map(String.init)
        var seen = Set<String>()
        return (accounts + saved).filter { !$0.isEmpty && seen.insert($0).inserted }
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
                                   ? "Google access has ended. Please connect this Gmail again."
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

    /// The `email` claim from Google's ID token (a JWT; its middle part is JSON).
    static func email(fromIDToken token: String) -> String? {
        claims(fromIDToken: token)?["email"] as? String
    }

    /// The ID token's payload, decoded and not verified: only for a token
    /// that came straight from Google's token endpoint (see `signInForIdentity`).
    static func claims(fromIDToken token: String) -> [String: Any]? {
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

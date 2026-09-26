import SwiftUI
import AuthenticationServices

// Optional sign in with Apple or Google, drawn once and used from Settings ›
// Account and from setup's `.account` step. Sortd keeps no account database:
// signing in is an identity for support and for the usage record, kept in
// this iPhone's Keychain (`AccountStore`). A cancel in Apple's sheet is
// quiet (no alert); anything else is reported through `onError` in the same
// plain English `AccountStore`/`AccountError` already use.
//
// `AccountStore` and its providers always compile (only the Sign in with
// Apple *capability* needs SORTD_SIGNIN), so this view does too.
struct SignInButtons: View {
    @Environment(\.colorScheme) private var scheme
    @State private var working = false
    /// Called with the account once the sign-in finishes. Never called on a
    /// cancel.
    var onSignedIn: (Account) -> Void = { _ in }
    /// A plain-English message to show, for anything that isn't a cancel.
    var onError: (String) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 10) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email]
                // Apple's sheet makes the scene inactive: keep the privacy
                // cover off it (ended in onCompletion, whatever the result).
                SystemPrompt.shared.begin()
            } onCompletion: { result in
                SystemPrompt.shared.end()
                let resolved: Result<Account, Error> = result
                    .mapError(AppleIdentityProvider.error(from:))
                    .flatMap { auth in
                        AppleIdentityProvider.account(from: auth).map { .success($0) } ?? .failure(AccountError.noIdentity)
                    }
                Task { await signIn(ResolvedIdentityProvider(result: resolved)) }
            }
            // Apple's button: black on light, white on dark, at least 44 pt.
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            // A fixed height: with only a minimum, the button fills whatever
            // container it is in (it swallowed the whole page in the bottom bar).
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            // Apple's button lets the corner radius follow the app's UI
            // (HIG, "Using the system-provided buttons"): a capsule here.
            .clipShape(.capsule)
            .disabled(working)

            Button {
                Task { await signIn(GoogleIdentityProvider()) }
            } label: {
                GoogleButtonLabel(working: working)
            }
            // Google's own capsule already carries the branding; `.primaryGlass()`
            // used to wrap it in a second, darker glass capsule.
            .googleButton()
            .disabled(working)
        }
    }

    private func signIn(_ provider: IdentityProvider) async {
        working = true
        defer { working = false }
        do {
            try await AccountStore.shared.signIn(with: provider)
            if let account = AccountStore.shared.current { onSignedIn(account) }
        } catch AccountError.cancelled {
            // Closed the sheet: nothing to say.
        } catch {
            onError(error.localizedDescription)
        }
    }
}

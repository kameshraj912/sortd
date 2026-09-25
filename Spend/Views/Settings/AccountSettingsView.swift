import SwiftUI
import SwiftData
import AuthenticationServices

// Settings › Account ships behind the SORTD_SIGNIN compile flag, off in
// both configs until the paid developer enrolment clears and the Sign in
// with Apple capability is on the App ID (Spend.entitlements already lists
// it). Without the capability the Apple button fails at run time with
// error 1000, so the row and this screen are compiled out. To turn it on:
// Xcode > Spend target > Build Settings > Active Compilation Conditions >
// add SORTD_SIGNIN to Debug and Release. `AccountStore` and its providers
// always compile, so the tests (fakes only) run everywhere.
#if SORTD_SIGNIN

/// Optional sign-in with Apple or Google. Sortd has no account server: the
/// sign-in is an identity for support and for the usage record, kept in
/// this iPhone's Keychain. Purchases stay on the phone either way.
struct AccountSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @State private var store = AccountStore.shared
    @State private var working = false
    @State private var failure: String?
    @State private var confirmingDelete = false

    var body: some View {
        List {
            ListPageTitle(title: "Account")
            if let account = store.current {
                signedIn(account)
            } else {
                signedOut
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.page)
        .brandedTitle("Account")
        .alert("Delete your account?", isPresented: $confirmingDelete) {
            Button("Delete Account", role: .destructive) { Task { await deleteAccount(alsoData: false) } }
            Button("Delete Account and All Data", role: .destructive) { Task { await deleteAccount(alsoData: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
        .alert("Sign-in didn't work", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK") {}
        } message: {
            Text(failure ?? "")
        }
    }

    // MARK: Signed out

    private var signedOut: some View {
        Section {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email]
            } onCompletion: { result in
                let resolved: Result<Account, Error> = result
                    .mapError(AppleIdentityProvider.error(from:))
                    .flatMap { auth in
                        AppleIdentityProvider.account(from: auth).map { .success($0) } ?? .failure(AccountError.noIdentity)
                    }
                Task { await signIn(ResolvedIdentityProvider(result: resolved)) }
            }
            // Apple's button: black on light, white on dark, at least 44 pt.
            .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
            .frame(maxWidth: .infinity, minHeight: 50)
            .disabled(working)

            Button {
                Task { await signIn(GoogleIdentityProvider()) }
            } label: {
                GoogleButtonLabel(working: working)
            }
            .primaryGlass()
            .disabled(working)
        } header: {
            BoldHeader("Sign In")
        } footer: {
            Text("Signing in is optional. It gives Sortd a way to know you if you ask for help. Your purchases stay on this iPhone either way. Sortd has no account server.")
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    // MARK: Signed in

    private func signedIn(_ account: Account) -> some View {
        Group {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signed in with \(account.provider.name)")
                        Text(account.maskedEmail ?? "Email not shared")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: account.provider == .apple ? "apple.logo" : "person.crop.circle")
                }
                .accessibilityElement(children: .combine)
                Button {
                    store.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .disabled(working)
            } header: {
                BoldHeader("Account")
            } footer: {
                Text("Sign Out forgets who you are on this iPhone. Your purchases stay.")
            }

            Section {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label {
                        Text(working ? "Deleting…" : "Delete Account")
                    } icon: {
                        if working { ProgressView() } else { Image(systemName: "person.crop.circle.badge.xmark") }
                    }
                }
                .foregroundStyle(Color.down)
                .disabled(working)
            } footer: {
                Text("Deleting asks \(account.provider.name) to cancel the sign-in and removes your usage record. You can also delete everything Sortd has stored on this iPhone.")
            }
        }
    }

    private var deleteMessage: String {
        let provider = store.current?.provider.name ?? "the provider"
        return "Sortd forgets who you are on this iPhone, asks \(provider) to cancel the sign-in and deletes your usage record. Your purchases stay unless you also delete all data."
    }

    // MARK: Actions

    private func signIn(_ provider: IdentityProvider) async {
        working = true
        defer { working = false }
        do {
            try await store.signIn(with: provider)
        } catch AccountError.cancelled {
            // Closed the sheet: nothing to say.
        } catch {
            failure = error.localizedDescription
        }
    }

    private func deleteAccount(alsoData: Bool) async {
        // The provider and the Worker are asked before the local wipe, so
        // this can take a moment when the network is slow.
        working = true
        defer { working = false }
        await store.deleteAccount()
        guard alsoData else { return }
        DataReset.deleteEverything(in: context)
        // Setup can't open over the Settings sheet: close it.
        Router.shared.settingsPath = []
        Router.shared.showingSettings = false
    }
}

#endif

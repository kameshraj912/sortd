import SwiftUI
import SwiftData

// Settings › Account ships behind the SORTD_SIGNIN compile flag, off in
// both configs until the paid developer enrolment clears and the Sign in
// with Apple capability is on the App ID (Spend.entitlements already lists
// it). Without the capability the Apple button fails at run time with
// error 1000, so the row and this screen are compiled out. To turn it on:
// Xcode > Spend target > Build Settings > Active Compilation Conditions >
// add SORTD_SIGNIN to Debug and Release. `AccountStore` and its providers
// always compile, so the tests (fakes only) run everywhere.
#if SORTD_SIGNIN

/// Optional sign-in with Apple or Google. Sortd keeps no account database: the
/// sign-in is an identity for support and for the usage record, kept in
/// this iPhone's Keychain. The account Worker (`worker/`) only revokes and
/// deletes, and stores nothing. Purchases stay on the phone either way.
struct AccountSettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var store = AccountStore.shared
    @State private var working = false
    @State private var notice: Notice?
    @State private var confirmingDelete = false
    /// Second step for "and All Data": it also deletes the iCloud backup,
    /// which a one-line note at the end of the first alert did not make
    /// clear (Raj lost his backup this way, 28 Sep).
    @State private var confirmingDeleteAll = false

    struct Notice {
        let title: String
        let message: String
    }

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
            Button("Delete Account and All Data", role: .destructive) { confirmingDeleteAll = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteMessage)
        }
        .alert("Delete your account and all data?", isPresented: $confirmingDeleteAll) {
            Button("Delete Everything", role: .destructive) { Task { await deleteAccount(alsoData: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(BackupDataSettingsView.deleteAllMessage(
                deletesCloudCopy: CloudBackup.shared.deletesCloudCopyOnReset))
        }
        .alert(notice?.title ?? "", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK") {}
        } message: {
            Text(notice?.message ?? "")
        }
    }

    // MARK: Signed out

    private var signedOut: some View {
        Section {
            SignInButtons(onSignedIn: { _ in },
                         onError: { notice = Notice(title: "Sign-in didn't work", message: $0) })
        } header: {
            BoldHeader("Sign In")
        } footer: {
            Text("Signing in is optional. It gives Sortd a way to know you if you ask for help. Your purchases stay on this iPhone either way. Sortd never sees your password.")
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
        guard let account = store.current else { return "" }
        var text = "Sortd forgets who you are on this iPhone, asks \(account.provider.name) to cancel the sign-in and deletes your usage record."
        if account.provider == .apple { text += " Apple will ask you to sign in once more to confirm." }
        #if SORTD_ICLOUD
        text += " Your purchases stay unless you also delete all data, on this iPhone and in iCloud."
        #else
        text += " Your purchases stay unless you also delete all data."
        #endif
        return text
    }

    // MARK: Actions

    private func deleteAccount(alsoData: Bool) async {
        // Offline, the store queues the server jobs and `Connectivity.catchUp`
        // finishes them when the phone is back online.
        // The provider and the Worker are asked before the local wipe, so
        // this can take a moment when the network is slow.
        working = true
        defer { working = false }
        let problems = await store.deleteAccount()
        if let first = problems.first {
            notice = Notice(title: "Account deleted, with one thing left", message: first)
        }
        guard alsoData else { return }
        DataReset.deleteEverything(in: context)
        // Setup can't open over the Settings sheet: close it.
        Router.shared.settingsPath = []
        Router.shared.showingSettings = false
    }
}

#endif

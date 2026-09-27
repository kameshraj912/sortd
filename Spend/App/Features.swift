/// Build-time feature switches. Fixed when the app is compiled; nothing can turn
/// them on later (App Review 2.3.1: no hidden or dormant features).
enum Features {
    /// Gmail receipts. On in every build: Release has SORTD_GMAIL, and v1 ships
    /// with Gmail. Submit to the App Store only after Google verifies the
    /// gmail.readonly scope (until then only 100 test users can connect).
    /// Removing SORTD_GMAIL from Release hides Gmail in the App Store build.
    static let gmail: Bool = {
        #if DEBUG || SORTD_GMAIL
        return true
        #else
        return false
        #endif
    }()

    /// Sign in with Apple / Google (sub-spec 4): the setup `.account` step
    /// and Settings › Account. Needs the paid developer account's Sign in
    /// with Apple capability, so it mirrors `gmail`'s pattern behind
    /// SORTD_SIGNIN (on in both configs; see AccountSettingsView.swift).
    static let signIn: Bool = {
        #if SORTD_SIGNIN
        return true
        #else
        return false
        #endif
    }()
}

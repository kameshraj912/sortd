/// Build-time feature switches. Fixed when the app is compiled; nothing can turn
/// them on later (App Review 2.3.1: no hidden or dormant features).
enum Features {
    /// Sign in with Apple / Google (sub-spec 4): the setup `.account` step
    /// and Settings › Account. Needs the paid developer account's Sign in
    /// with Apple capability, so it sits behind SORTD_SIGNIN (on in both
    /// configs; see AccountSettingsView.swift).
    static let signIn: Bool = {
        #if SORTD_SIGNIN
        return true
        #else
        return false
        #endif
    }()
}

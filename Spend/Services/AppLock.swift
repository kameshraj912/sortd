import SwiftUI
import LocalAuthentication

/// Face ID / passcode lock. Locks on launch and when you come back after
/// more than a minute away. Never locks during first-run setup.
@Observable @MainActor
final class AppLock {
    static let enabledKey = "appLockEnabled"
    /// Seconds away before the app locks again.
    nonisolated static let grace: TimeInterval = 60

    private(set) var isLocked: Bool
    private(set) var authenticating = false
    /// When the app last stopped being active. Nil until it has been.
    private var lastActive: Date?

    init() {
        let defaults = UserDefaults.standard
        isLocked = defaults.bool(forKey: Self.enabledKey)
            && defaults.bool(forKey: OnboardingView.doneKey)
            && !RootView.forceSetup
    }

    /// Pure rule: lock when on and the app was never active (launch) or
    /// has been away for more than `grace` seconds.
    nonisolated static func shouldLock(lastActive: Date?, now: Date, enabled: Bool) -> Bool {
        guard enabled else { return false }
        guard let lastActive else { return true }
        return now.timeIntervalSince(lastActive) > grace
    }

    /// Call on every scene phase change.
    func sceneChanged(to phase: ScenePhase, enabled: Bool, onboarded: Bool, now: Date = .now) {
        guard onboarded, enabled else {
            isLocked = false
            if phase != .active { lastActive = now }
            return
        }
        switch phase {
        case .active:
            // The Face ID sheet itself makes the app briefly inactive.
            if !authenticating, !isLocked, Self.shouldLock(lastActive: lastActive, now: now, enabled: enabled) {
                isLocked = true
            }
        default:
            if !isLocked, !authenticating { lastActive = now }
        }
    }

    func unlock() async {
        guard isLocked, !authenticating else { return }
        authenticating = true
        let ok = await Self.authenticate(reason: "Unlock Sortd to see your spending.")
        authenticating = false
        if ok {
            isLocked = false
            lastActive = .now
        }
    }

    /// Face ID or Touch ID, with the device passcode as a fallback.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    /// "Face ID", "Touch ID", "Optic ID" or "Passcode", for labels.
    static var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return switch context.biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "Passcode"
        }
    }

    static var methodSymbol: String {
        switch methodName {
        case "Face ID": "faceid"
        case "Touch ID": "touchid"
        case "Optic ID": "opticid"
        default: "lock"
        }
    }
}

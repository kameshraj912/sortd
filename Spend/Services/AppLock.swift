import SwiftUI
import LocalAuthentication

/// Face ID / passcode lock. Locks on launch and when you come back after the
/// stored `RequireAfter` grace period (immediately, by default). Never locks
/// during first-run setup.
@Observable @MainActor
final class AppLock {
    static let enabledKey = "appLockEnabled"
    static let requireAfterKey = "appLockRequireAfter"

    /// How long Sortd can sit in the background before it locks again.
    /// Banks default to `.immediately`; WhatsApp-style options are also here.
    enum RequireAfter: Int, CaseIterable, Identifiable {
        case immediately = 0
        case oneMinute = 60
        case fifteenMinutes = 900
        case oneHour = 3600

        var id: Int { rawValue }

        var label: String {
            switch self {
            case .immediately: "Immediately"
            case .oneMinute: "After 1 minute"
            case .fifteenMinutes: "After 15 minutes"
            case .oneHour: "After 1 hour"
            }
        }
    }

    /// The stored choice, defaulting to `.immediately` (banks lock at once).
    static var requireAfter: RequireAfter {
        RequireAfter(rawValue: UserDefaults.standard.integer(forKey: requireAfterKey)) ?? .immediately
    }

    private(set) var isLocked: Bool
    private(set) var authenticating = false
    /// When the app last stopped being active. Nil until it has been.
    private var lastActive: Date?
    /// When the app last went to `.background` (not `.inactive`, which also
    /// happens transiently on the way back and must not count). Nil while
    /// the app has not backgrounded since launch or since it last unlocked.
    private var backgroundedAt: Date?

    init() {
        let defaults = UserDefaults.standard
        isLocked = defaults.bool(forKey: Self.enabledKey)
            && defaults.bool(forKey: OnboardingView.doneKey)
            && !RootView.forceSetup
    }

    /// Pure rule: lock when on and the app was never active (launch) or
    /// has been away for more than `grace` seconds.
    nonisolated static func shouldLock(lastActive: Date?, now: Date, enabled: Bool, grace: TimeInterval) -> Bool {
        guard enabled else { return false }
        guard let lastActive else { return true }
        return now.timeIntervalSince(lastActive) > grace
    }

    /// Call on every scene phase change.
    func sceneChanged(to phase: ScenePhase, enabled: Bool, onboarded: Bool, now: Date = .now) {
        guard onboarded, enabled else {
            isLocked = false
            if phase == .background { backgroundedAt = now }
            else if phase == .active { lastActive = now }
            return
        }
        switch phase {
        case .active:
            // The Face ID sheet itself makes the app briefly inactive, not
            // backgrounded, so `backgroundedAt` is untouched by it.
            if !authenticating, !isLocked {
                let awayStart = backgroundedAt ?? lastActive
                let grace = TimeInterval(Self.requireAfter.rawValue)
                if Self.shouldLock(lastActive: awayStart, now: now, enabled: enabled, grace: grace) {
                    isLocked = true
                }
            }
            backgroundedAt = nil
            if !isLocked { lastActive = now }
        case .background:
            backgroundedAt = now
        default:
            // `.inactive` on the way back from the background (and on the
            // way out) is a transient step — App Switcher, an interruption,
            // the Face ID sheet itself. Treating it as real use resets the
            // idle clock and the app never locks again after the first
            // unlock, so it must change nothing here.
            break
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
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // The iPhone passcode was removed after App Lock was turned on.
            // Nothing can unlock Sortd then, and the phone itself is open, so
            // the lock protects nothing: switch it off rather than lock the
            // owner out of their data for good.
            if error?.domain == LAErrorDomain, error?.code == LAError.Code.passcodeNotSet.rawValue {
                UserDefaults.standard.set(false, forKey: enabledKey)
                return true
            }
            return false
        }
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

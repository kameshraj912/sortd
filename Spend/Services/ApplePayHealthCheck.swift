import Foundation

/// The excluded merchant name used by "Check the Shortcut" (spec 2026-09-26,
/// failsafe #11, added in full separately) — declared here first because
/// `ApplePayStatus.realTaps`/`needsCheckCount` and `Activation.detect` need
/// to exclude it from day one, the same way they already exclude
/// `LogPurchaseIntent.legacyTestMerchant`: never a real tap, never real
/// spending, never activation.
enum ApplePayHealthCheck {
    static let merchant = "Sortd Check"
}

import Foundation
import SwiftData

/// The aha moment (overhaul sub-spec 6): the first purchase Sortd logged by
/// itself, from an Apple Pay tap or a Gmail receipt. Sample data and the
/// "Send a Test Tap" purchase never count: they prove nothing about the
/// person's own spending.
///
/// Pure detection plus two once-only flags in UserDefaults. Home reads the
/// flags and shows the card; nothing here draws anything or asks for a
/// permission. `watchSaves` is the one hook, on the same `didSave` the
/// widget and iCloud backup use, so the logger stays free of it.
enum Activation {
    enum Source: String { case tap, email }

    /// Set once, when the first qualifying purchase is saved.
    static let seenKey = "activationSeen"
    /// Set once the person has answered the single notification ask on
    /// Home (yes or no). Declined means never asked again.
    static let askedKey = "notificationAskShown"

    /// Which automatic source this purchase came from, or nil when it does
    /// not count as the aha.
    static func detect(_ t: Transaction) -> Source? {
        guard t.note != DemoData.marker else { return nil }
        guard t.merchant != TapTestButton.testMerchant, t.rawMerchant != TapTestButton.testMerchant else { return nil }
        let seen = t.seenIn
        if seen.contains(.tap) { return .tap }
        if seen.contains(.email) { return .email }
        return nil
    }

    /// Records the aha once per install. Returns the source the first time a
    /// qualifying purchase is seen, nil for every call after (and for any
    /// purchase that does not qualify).
    @discardableResult
    static func recordIfFirst(_ t: Transaction, defaults: UserDefaults = .standard) -> Source? {
        guard let source = detect(t), !defaults.bool(forKey: seenKey) else { return nil }
        defaults.set(true, forKey: seenKey)
        return source
    }

    /// The one notification ask comes after the aha and only until answered.
    static func shouldAskForNotifications(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: seenKey) && !defaults.bool(forKey: askedKey)
    }

    static func markNotificationAsked(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: askedKey)
    }

    // MARK: - Hook

    /// After every save to the store, until the aha has happened: look for
    /// the first purchase a tap or an email reported. Call once at launch.
    @MainActor
    static func watchSaves() {
        let context = SpendStore.container.mainContext
        guard !UserDefaults.standard.bool(forKey: seenKey) else { return }
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: context, queue: .main) { _ in
            MainActor.assumeIsolated { check(in: context) }
        }
    }

    /// One fetch of the rows an automatic source has seen, then `recordIfFirst`
    /// on each. A no-op once the flag is set.
    @MainActor
    static func check(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: seenKey) else { return }
        let tap = TxnSource.tap.rawValue, email = TxnSource.email.rawValue
        let candidates = (try? context.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.seenInRaw.contains(tap) || $0.seenInRaw.contains(email) }))) ?? []
        for t in candidates where recordIfFirst(t, defaults: defaults) != nil { return }
    }
}

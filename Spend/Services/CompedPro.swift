import Foundation
import CryptoKit

/// Pro, given away.
///
/// For friends, testers, and anyone who finds the door. It unlocks the same
/// features a purchase does, on this iPhone only, and it never touches
/// StoreKit — a comped unlock is Sortd's own business, not Apple's.
///
/// Two things this is deliberately not:
///
/// * **Not a way to sell Pro outside the App Store.** Apple requires
///   in-app purchase for unlocking features, and codes handed round for
///   money would be exactly what Guideline 3.1.1 forbids. These are gifts.
/// * **Not security.** The codes are hashed so they aren't sitting in the
///   binary as plain strings, but anyone determined can find them, and
///   that's fine. The worst case is somebody gets a spending tracker free.
nonisolated enum CompedPro {

    static let key = "compedPro"
    static let sourceKey = "compedProSource"

    /// SHA-256 of each code, lowercased and stripped of spaces and dashes.
    /// Kept as hashes so the codes aren't readable in the app binary.
    ///
    /// A note on the nods. Most of these are riffs rather than quotes —
    /// "I am the one who budgets" is original wording that only lands if you
    /// know the line it's playing with, which is parody, not copying. The
    /// rest are ordinary English ("greed is good", "what's in the box") or
    /// generic terms. Nothing here is a registered mark being used as one.
    ///
    /// The rule that keeps it that way: a code is something a person types
    /// in, never something Sortd displays, and none of it goes in the App
    /// Store listing, the screenshots or the website — which is where a
    /// trademark claim would actually have legs.
    private static let accepted: [String: String] = [
        // "iamtheonewhobudgets"
        "da5ed46eec66ccb2c8d5f094cbdcd72df785089a8682abd28f72b1d2ac900d94": "the one who budgets",
        // "thereisnobudget"
        "393d33c00be7732bab500b3228ab528c00f4bef7f6bb8933c5fa65106a90f11a": "no budget",
        // "wedontalkaboutbrunch"
        "3683716de922865ee2153ea1305964de8059c51cc8fe3c927d03d91aebb60a6d": "brunch",
        // "ihavenomoneyandimustscream"
        "4eb40fc3d71b35fdc6b56380720ebb32ffaccaf2fed9c19d2616dc870b99e8bc": "no money",
        // "greedisgood"
        "b0cd76b7d7829362d581b739c0b295abf53182792609078bb17a9dd917ffba7c": "greed",
        // "whatsinthebox"
        "34b8b147269cfb1b1a2f2cb4c85b6975a5472151a111b8fe119fc5c7b16cbbfd": "the box",
        // "latestagecapitalism"
        "4851ae8433be52645fed98c4c77cea2be97a2500f94aa3d2d1730737b36c6097": "late stage",
        // "sortdbyraj"
        "f717ee0ac4a34123173cfc39b82b94f64d0158ebb791174cacd56e7bbfe2a248": "the founder",
    ]

    static func normalise(_ code: String) -> String {
        code.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }

    static func hash(_ code: String) -> String {
        let digest = SHA256.hash(data: Data(normalise(code).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// True when this build has been comped.
    static func isActive(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: key)
    }

    enum Result: Equatable {
        case unlocked(String)
        case alreadyUnlocked
        case notACode

        var isSuccess: Bool {
            switch self {
            case .unlocked, .alreadyUnlocked: true
            case .notACode: false
            }
        }
    }

    @discardableResult
    static func redeem(_ code: String, _ defaults: UserDefaults = .standard) -> Result {
        guard !normalise(code).isEmpty else { return .notACode }
        guard let name = accepted[hash(code)] else { return .notACode }
        if isActive(defaults) { return .alreadyUnlocked }
        defaults.set(true, forKey: key)
        defaults.set(name, forKey: sourceKey)
        return .unlocked(name)
    }

    /// Only used by Delete All Data, which means it.
    static func clear(_ defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
        defaults.removeObject(forKey: sourceKey)
    }
}

/// The counter behind the hidden door.
///
/// Tapping the version row in Settings five times opens the code sheet. Five
/// is the number Apple itself uses for the hidden developer settings, which
/// is long enough that nobody gets there by accident and short enough that
/// somebody who has been told about it doesn't give up.
@MainActor
@Observable
final class SecretKnock {
    static let shared = SecretKnock()

    private(set) var count = 0
    var isOpen = false

    /// How close they are, once they're close enough to be trying.
    var hint: String? {
        switch count {
        case 3: "Keep going."
        case 4: "One more."
        default: nil
        }
    }

    func knock() {
        count += 1
        if count >= 5 {
            count = 0
            isOpen = true
        }
    }

    func reset() { count = 0 }

    private init() {}
}

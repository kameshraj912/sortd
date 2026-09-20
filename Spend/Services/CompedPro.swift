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
    private static let accepted: [String: String] = [
        // "maximumeffort"
        "d628b09f0d6531337fa86f049c8060db85cdb72881768319f52cae4a1a9b1bc1": "maximum effort",
        // "chimichangas"
        "a698a841b4e5c9d47dbc94e1880f021692b940a8b1128af064ab261a838af7d2": "chimichangas",
        // "sortdsortd"
        "784fa9dc58bbc3101826e4dd352d25b4ab2a438bbc0b8fe89e60838db62c46c1": "the long way round",
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

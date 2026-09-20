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
        // "spendnowcrylater"
        "223b717bf506de9a06ae1d341dd27a4287062d4bb8b374f1bbbeac4c30fb231a": "cry later",
        // "futuremeproblem"
        "9faf31d2f381c06ff740358decf1cb4e64881d76f96676413c66eed3ed5fb5b8": "future me",
        // "denialisabudget"
        "a07e69d25da4cbf2ef57fde50d583f7eb9247aa7fbdacc12959c19b3af351687": "denial",
        // "itwasonsale"
        "13011659da558d82420f7092afeea5db12a2d4fdb62cf977775683b4222856df": "on sale",
        // "ineedthisactually"
        "6e00920bd2bfd53d0d11c0c79ef65906b524117055df5191a7b8f5d1633f3e1c": "need, apparently",
        // "iamtheonewhobudgets"
        "da5ed46eec66ccb2c8d5f094cbdcd72df785089a8682abd28f72b1d2ac900d94": "the one who budgets",
        // "ihavenomoneyandimustscream"
        "4eb40fc3d71b35fdc6b56380720ebb32ffaccaf2fed9c19d2616dc870b99e8bc": "the scream",
        // "deathandtaxes"
        "2677a37b90dac8608ce39194c1732d6ad9a861df1194171262a06ac5a1c81c63": "certainties",
        // "latestagecapitalism"
        "4851ae8433be52645fed98c4c77cea2be97a2500f94aa3d2d1730737b36c6097": "late stage",
        // "treatyourselftodebt"
        "522570619196f8855da9ac5b1babff956dab1ab2a02af4f3b6b9464b6e6c71b5": "treat yourself",
        // "thebankdisagrees"
        "b43b110d1711dcf93cdb6a454161e6ada1f9e384b4958974735642e13ace4d88": "the bank disagrees",
        // "itsaninvestment"
        "5e54b3671b57266505ba9d87ac9be794a17511f780aec3b7ce8394c6a24ee1d1": "an investment",
        // "moneyhasleftthechat"
        "09543b3e6c29976abb7e5ae4e56155ff3ccd3fad2146a76a3ff7bbf2b2e08dd1": "left the chat",
        // "paydayisamyth"
        "65a27c190dfee29c16c9f202f478f0bbf1b979948e02b19cc47deb8ea2013715": "payday",
        // "brokebutaesthetic"
        "8f65865ae448e2122e04cd7c4272a3f5aa7ea6acec49e6f97f4c5d75c97a7689": "aesthetic",
        // "onelastcoffee"
        "8621069122bf6a3fc3908ffb1149f2c40e3019a42d5b30f6e721b300ef11020e": "one last coffee",
        // "thealgorithmmademedoit"
        "6b75afede069e5e7b3150d9f9f62d43fa7d15edff4d28fc7c86fe1c6c4d75d36": "the algorithm",
        // "roundingerror"
        "97a8e6e9d7bc164a2c29e7f32bc6d244bf7fe752957991d75c57c44a0ab4d344": "rounding error",
        // "cashisamemory"
        "fb839a86df475d622753e858131e9601ec80e9290a66cd5c9ee446167a6e71b2": "a memory",
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

    /// Which code was used, if any. The app has no server, so this is the
    /// only record that exists — it lives on that one iPhone and nothing
    /// reports it anywhere. To know who redeemed what, hand each person a
    /// different code and ask them what Settings says.
    static func source(_ defaults: UserDefaults = .standard) -> String? {
        guard isActive(defaults) else { return nil }
        return defaults.string(forKey: sourceKey)
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

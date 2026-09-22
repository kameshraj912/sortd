import CryptoKit
import Foundation
import Security

/// The forwarding inbox's key pair and HPKE decryption.
///
/// The server encrypts each forwarded email to this phone's public key and
/// only ever stores the ciphertext. The private key never leaves the phone:
/// on a real iPhone it lives in the Secure Enclave (the Keychain only holds
/// an encrypted handle that only this phone's Secure Enclave can use). The
/// simulator has no Secure Enclave, so there it's a normal key in the
/// Keychain, this device only.
///
/// Suite: HPKE base mode, DHKEM(P-256, HKDF-SHA256), HKDF-SHA256, AES-256-GCM
/// (RFC 9180). The Worker in `inbox/` uses the same suite and `info`.
nonisolated enum InboxCrypto {
    static let suite = HPKE.Ciphersuite.P256_SHA256_AES_GCM_256
    /// The name the Worker checks at registration.
    static let suiteName = "P256_SHA256_AES_GCM_256"
    /// Binds every message to this protocol version. Must match `INFO` in inbox/src/hpke.js.
    static let info = Data("sortd-inbox/v1".utf8)

    enum KeyError: Error { case unreadable }

    enum Key {
        case enclave(SecureEnclave.P256.KeyAgreement.PrivateKey)
        case software(P256.KeyAgreement.PrivateKey)

        /// A new key: in the Secure Enclave when the phone has one.
        /// Usable after first unlock, so a background check can read mail.
        static func generate() throws -> Key {
            if SecureEnclave.isAvailable {
                var error: Unmanaged<CFError>?
                guard let access = SecAccessControlCreateWithFlags(
                    nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, .privateKeyUsage, &error) else {
                    throw error.map { $0.takeRetainedValue() as Error } ?? KeyError.unreadable
                }
                return .enclave(try SecureEnclave.P256.KeyAgreement.PrivateKey(compactRepresentable: false, accessControl: access))
            }
            return .software(P256.KeyAgreement.PrivateKey(compactRepresentable: false))
        }

        /// The public key the server encrypts to: 65 bytes, uncompressed (x9.63).
        var publicKey: Data {
            switch self {
            case .enclave(let k): k.publicKey.x963Representation
            case .software(let k): k.publicKey.x963Representation
            }
        }

        var isInSecureEnclave: Bool {
            if case .enclave = self { return true }
            return false
        }

        /// For the Keychain. The enclave form is useless on any other device.
        var stored: String {
            switch self {
            case .enclave(let k): "se:" + k.dataRepresentation.base64EncodedString()
            case .software(let k): "sw:" + k.rawRepresentation.base64EncodedString()
            }
        }

        init(stored: String) throws {
            let kind = stored.prefix(3)
            guard let data = Data(base64Encoded: String(stored.dropFirst(3))) else { throw KeyError.unreadable }
            switch kind {
            case "se:": self = .enclave(try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: data))
            case "sw:": self = .software(try P256.KeyAgreement.PrivateKey(rawRepresentation: data))
            default: throw KeyError.unreadable
            }
        }

        /// Decrypts one message. `aad` is the message id the server stored it under:
        /// a ciphertext moved to another id fails to open.
        func open(enc: Data, ciphertext: Data, aad: Data) throws -> Data {
            switch self {
            case .enclave(let k):
                var r = try HPKE.Recipient(privateKey: k, ciphersuite: InboxCrypto.suite, info: InboxCrypto.info, encapsulatedKey: enc)
                return try r.open(ciphertext, authenticating: aad)
            case .software(let k):
                var r = try HPKE.Recipient(privateKey: k, ciphersuite: InboxCrypto.suite, info: InboxCrypto.info, encapsulatedKey: enc)
                return try r.open(ciphertext, authenticating: aad)
            }
        }
    }

    /// Encrypts like the server does. Tests only.
    static func seal(_ plaintext: Data, to publicKey: Data, aad: Data) throws -> (enc: Data, ciphertext: Data) {
        let pk = try P256.KeyAgreement.PublicKey(x963Representation: publicKey)
        var sender = try HPKE.Sender(recipientKey: pk, ciphersuite: suite, info: info)
        let ct = try sender.seal(plaintext, authenticating: aad)
        return (sender.encapsulatedKey, ct)
    }
}

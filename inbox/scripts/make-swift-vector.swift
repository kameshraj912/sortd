// Writes test/fixtures/swift-to-js.json: a message sealed by Apple's CryptoKit
// HPKE, for the Worker's tests to open. Proves the other direction of interop.
// Uses the same test-only recipient key as js-to-swift.json.
// Run on a Mac from inbox/:  swift scripts/make-swift-vector.swift
// (CryptoKit picks a fresh ephemeral key, so the output changes each run.)
import CryptoKit
import Foundation

func b64u(_ d: Data) -> String {
    d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
func unb64u(_ s: String) -> Data {
    var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while t.count % 4 != 0 { t += "=" }
    return Data(base64Encoded: t)!
}

let here = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let jsVector = try JSONSerialization.jsonObject(with: Data(contentsOf: here.appending(path: "test/fixtures/js-to-swift.json"))) as! [String: Any]
let pk = try P256.KeyAgreement.PublicKey(x963Representation: unb64u(jsVector["recipientPublicKeyB64u"] as! String))

let id = "mfq2xa000-swiftVector00001"
let plaintext = Data(#"{"v":1,"kind":"mail","from":"CryptoKit <test@example.com>","subject":"Sealed by Swift","text":"Total $1.00"}"#.utf8)
var sender = try HPKE.Sender(recipientKey: pk, ciphersuite: .P256_SHA256_AES_GCM_256, info: Data("sortd-inbox/v1".utf8))
let ct = try sender.seal(plaintext, authenticating: Data(id.utf8))

let out: [String: Any] = [
    "note": "Made by inbox/scripts/make-swift-vector.swift with CryptoKit HPKE. Test key only.",
    "suite": "P256_SHA256_AES_GCM_256",
    "id": id,
    "enc": b64u(sender.encapsulatedKey),
    "ct": b64u(ct),
    "plaintext": String(decoding: plaintext, as: UTF8.self),
]
let json = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
try (json + Data("\n".utf8)).write(to: here.appending(path: "test/fixtures/swift-to-js.json"))
print("wrote test/fixtures/swift-to-js.json")

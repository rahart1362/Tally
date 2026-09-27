import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// RFC 7636 Proof Key for Code Exchange, S256 only (Canvas accepts only S256).
public struct PKCEPair: Sendable, Equatable, Codable {
    public let verifier: String
    public let challenge: String

    /// 32 random bytes → a 43-character base64url verifier.
    public static func make(using rng: inout some RandomNumberGenerator) -> PKCEPair {
        let verifier = Base64URL.randomToken(byteCount: 32, using: &rng)
        return PKCEPair(verifier: verifier, challenge: challenge(for: verifier))
    }

    public static func challenge(for verifier: String) -> String {
        Base64URL.encode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
}

enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func randomToken(byteCount: Int, using rng: inout some RandomNumberGenerator) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for i in bytes.indices { bytes[i] = UInt8.random(in: .min ... .max, using: &rng) }
        return encode(Data(bytes))
    }
}

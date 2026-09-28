#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// 12-byte header, authenticated as AES-GCM additional data (AAD):
/// magic "TLYV" | format u8 (=1) | file u8 | flags u16 (=0 in v1) | keyID u32 BE
public struct SealedBlobHeader: Equatable, Sendable {
    public static let magic: [UInt8] = [0x54, 0x4C, 0x59, 0x56]
    public static let currentFormat: UInt8 = 1
    public static let byteCount = 12
    public static let minimumBlobSize = byteCount + 12 + 16 // header + nonce + tag

    public let file: StoreFile
    public let keyID: UInt32

    public init(file: StoreFile, keyID: UInt32) { self.file = file; self.keyID = keyID }

    public var encoded: Data {
        var d = Data(Self.magic)
        d.append(contentsOf: [Self.currentFormat, file.rawValue, 0x00, 0x00])
        for shift in stride(from: 24, through: 0, by: -8) { d.append(UInt8(truncatingIfNeeded: keyID >> UInt32(shift))) }
        return d
    }

    /// Parses the not-yet-authenticated header; `SealedBlob.open` authenticates it as AAD.
    public static func decode(from blob: Data) throws -> SealedBlobHeader {
        guard blob.count >= minimumBlobSize else { throw VaultError.malformed }
        let b = [UInt8](blob.prefix(byteCount))
        guard Array(b[0..<4]) == magic else { throw VaultError.malformed }
        guard b[4] == currentFormat, b[6] == 0, b[7] == 0 else { throw VaultError.unsupportedFormat(b[4]) }
        guard let file = StoreFile(rawValue: b[5]) else { throw VaultError.malformed }
        return SealedBlobHeader(file: file, keyID: b[8..<12].reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
    }
}

/// blob = header || nonce(12) || ciphertext || tag(16). AAD = header. The nonce is always
/// random in production; only `@testable` known-answer tests may pin it.
public enum SealedBlob {
    public static func seal(_ plaintext: Data, header: SealedBlobHeader, key: SymmetricKey) throws -> Data {
        try seal(plaintext, header: header, key: key, nonce: AES.GCM.Nonce())
    }

    static func seal(_ plaintext: Data, header: SealedBlobHeader, key: SymmetricKey, nonce: AES.GCM.Nonce) throws -> Data {
        let aad = header.encoded
        let box = try AES.GCM.seal(plaintext, using: key, nonce: nonce, authenticating: aad)
        guard let combined = box.combined else { throw VaultError.malformed }
        return aad + combined
    }

    public static func open(_ blob: Data, key: SymmetricKey) throws -> (header: SealedBlobHeader, plaintext: Data) {
        let header = try SealedBlobHeader.decode(from: blob)
        do {
            let box = try AES.GCM.SealedBox(combined: Data(blob.dropFirst(SealedBlobHeader.byteCount)))
            return (header, try AES.GCM.open(box, using: key, authenticating: Data(blob.prefix(SealedBlobHeader.byteCount))))
        } catch {
            throw VaultError.authenticationFailed
        }
    }
}

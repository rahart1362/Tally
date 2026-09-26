// ASSESSMENT HARNESS ONLY: mirrors the subset of the CryptoKit / swift-crypto API that TallyVault uses,
// backed by the system libcrypto, so the spec compiles and runs offline. Not for production.
import Foundation
import CLibCrypto

public enum CryptoKitError: Error, Equatable { case incorrectKeySize, incorrectParameterSize, authenticationFailure, underlyingCoreCryptoError(error: Int32) }

public struct SymmetricKeySize: Sendable { public let bitCount: Int
    public init(bitCount: Int) { self.bitCount = bitCount }
    public static let bits256 = SymmetricKeySize(bitCount: 256) }

private func randomBytes(_ n: Int) -> [UInt8] {
    var b = [UInt8](repeating: 0, count: n); precondition(RAND_bytes(&b, Int32(n)) == 1); return b }

public struct SymmetricKey: Sendable {
    fileprivate let bytes: [UInt8]
    public init(size: SymmetricKeySize) { bytes = randomBytes(size.bitCount / 8) }
    public init<D: ContiguousBytes>(data: D) { bytes = data.withUnsafeBytes { Array($0) } }
    public var bitCount: Int { bytes.count * 8 }
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try bytes.withUnsafeBytes(body) }
}

public enum AES { public enum GCM {
    public struct Nonce: Sendable { fileprivate let bytes: [UInt8]
        public init() { bytes = randomBytes(12) }
        public init<D: DataProtocol>(data: D) throws { guard data.count >= 12 else { throw CryptoKitError.incorrectParameterSize }; bytes = Array(data) } }
    public struct SealedBox: Sendable {
        public let nonce: Nonce; public let ciphertext: Data; public let tag: Data
        public var combined: Data? { nonce.bytes.count == 12 ? Data(nonce.bytes) + ciphertext + tag : nil }
        public init<D: DataProtocol>(combined: D) throws {
            let a = Array(combined); guard a.count >= 28 else { throw CryptoKitError.incorrectParameterSize }
            nonce = try Nonce(data: a[0..<12]); ciphertext = Data(a[12..<(a.count - 16)]); tag = Data(a[(a.count - 16)...]) }
        fileprivate init(nonce: Nonce, ciphertext: Data, tag: Data) { self.nonce = nonce; self.ciphertext = ciphertext; self.tag = tag }
    }
    public static func seal<P: DataProtocol, A: DataProtocol>(_ message: P, using key: SymmetricKey, nonce: Nonce? = nil, authenticating aad: A) throws -> SealedBox {
        guard key.bytes.count == 32 else { throw CryptoKitError.incorrectKeySize }
        let n = nonce ?? Nonce(); let pt = Array(message), ad = Array(aad)
        guard let ctx = EVP_CIPHER_CTX_new() else { throw CryptoKitError.underlyingCoreCryptoError(error: -1) }
        defer { EVP_CIPHER_CTX_free(ctx) }
        var out = [UInt8](repeating: 0, count: pt.count + 16), len: Int32 = 0, tag = [UInt8](repeating: 0, count: 16)
        guard EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), nil, nil, nil) == 1,
              EVP_CIPHER_CTX_ctrl(ctx, TALLY_GCM_SET_IVLEN, Int32(n.bytes.count), nil) == 1,
              EVP_EncryptInit_ex(ctx, nil, nil, key.bytes, n.bytes) == 1,
              ad.isEmpty || EVP_EncryptUpdate(ctx, nil, &len, ad, Int32(ad.count)) == 1,
              EVP_EncryptUpdate(ctx, &out, &len, pt, Int32(pt.count)) == 1 else { throw CryptoKitError.underlyingCoreCryptoError(error: -2) }
        let written = Int(len)
        guard EVP_EncryptFinal_ex(ctx, &out[written], &len) == 1,
              EVP_CIPHER_CTX_ctrl(ctx, TALLY_GCM_GET_TAG, 16, &tag) == 1 else { throw CryptoKitError.underlyingCoreCryptoError(error: -3) }
        return SealedBox(nonce: n, ciphertext: Data(out[0..<(written + Int(len))]), tag: Data(tag))
    }
    public static func seal<P: DataProtocol>(_ message: P, using key: SymmetricKey, nonce: Nonce? = nil) throws -> SealedBox {
        try seal(message, using: key, nonce: nonce, authenticating: Data()) }
    public static func open<A: DataProtocol>(_ box: SealedBox, using key: SymmetricKey, authenticating aad: A) throws -> Data {
        guard key.bytes.count == 32 else { throw CryptoKitError.incorrectKeySize }
        let ct = Array(box.ciphertext), ad = Array(aad); var tag = Array(box.tag)
        guard let ctx = EVP_CIPHER_CTX_new() else { throw CryptoKitError.underlyingCoreCryptoError(error: -1) }
        defer { EVP_CIPHER_CTX_free(ctx) }
        var out = [UInt8](repeating: 0, count: ct.count + 16), len: Int32 = 0
        guard EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), nil, nil, nil) == 1,
              EVP_CIPHER_CTX_ctrl(ctx, TALLY_GCM_SET_IVLEN, Int32(box.nonce.bytes.count), nil) == 1,
              EVP_DecryptInit_ex(ctx, nil, nil, key.bytes, box.nonce.bytes) == 1,
              ad.isEmpty || EVP_DecryptUpdate(ctx, nil, &len, ad, Int32(ad.count)) == 1,
              EVP_DecryptUpdate(ctx, &out, &len, ct, Int32(ct.count)) == 1,
              EVP_CIPHER_CTX_ctrl(ctx, TALLY_GCM_SET_TAG, 16, &tag) == 1 else { throw CryptoKitError.underlyingCoreCryptoError(error: -2) }
        let written = Int(len)
        guard EVP_DecryptFinal_ex(ctx, &out[written], &len) == 1 else { throw CryptoKitError.authenticationFailure }
        return Data(out[0..<(written + Int(len))])
    }
}}

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import Testing
@testable import TallyStore

extension Data {
    init(hex: String) {
        self.init(stride(from: 0, to: hex.count, by: 2).map { i -> UInt8 in
            let s = hex.index(hex.startIndex, offsetBy: i)
            return UInt8(hex[s..<hex.index(s, offsetBy: 2)], radix: 16)!
        })
    }
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

/// Known answers computed independently with python-cryptography 50.0.1 (OpenSSL 4.0.2); see
/// `docs/pmo/encryption-spec/tools/vectors.py`. TC16 = McGrew & Viega GCM spec, Test Case 16
/// (AES-256, 96-bit IV, with AAD). Ported from `docs/pmo/encryption-spec` unchanged in meaning
/// (WP-ENC-01): same vectors, same negative cases, Swift Testing instead of XCTest.
@Suite("SealedBlob: header, envelope, and known-answer vectors")
struct VaultBlobTests {
    let key = SymmetricKey(data: Data((0..<32).map { UInt8($0) }))
    let nonce = Data((0xa0...0xab).map { UInt8($0) })
    static let tv1 = "544c59560101000000000001a0a1a2a3a4a5a6a7a8a9aaab9d3a0a0f7ffa7facb577066bd84fc946655a49e313646e"

    @Test func primitiveMatchesGCMSpecTestCase16() throws {
        let box = try AES.GCM.seal(
            Data(hex: "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39"),
            using: SymmetricKey(data: Data(hex: "feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308")),
            nonce: try AES.GCM.Nonce(data: Data(hex: "cafebabefacedbaddecaf888")),
            authenticating: Data(hex: "feedfacedeadbeeffeedfacedeadbeefabaddad2"))
        #expect(box.ciphertext.hex == "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662")
        #expect(box.tag.hex == "76fc6ece0f4e1768cddf8853bb2d551b")
    }

    struct EnvelopeCase: Sendable {
        let file: StoreFile
        let keyID: UInt32
        let plaintext: Data
        let hex: String
    }

    static let envelopeCases: [EnvelopeCase] = [
        EnvelopeCase(file: .snapshot, keyID: 1, plaintext: Data(#"{"v":1}"#.utf8), hex: tv1),
        EnvelopeCase(file: .snapshot, keyID: 1, plaintext: Data(),
                     hex: "544c59560101000000000001a0a1a2a3a4a5a6a7a8a9aaab77dd7c44b89e4d75d3af373e7244d192"),
        EnvelopeCase(file: .glance, keyID: 7, plaintext: Data("Due: MATH 221 \u{2013} Problem Set 4".utf8),
                     hex: "544c59560102000000000007a0a1a2a3a4a5a6a7a8a9aaaba26d1917658643eb2a45b5e1365a225ee38c0962fdd52e09f12e75e30b8b41a3e8788465b76b6f094732287b312360"),
        EnvelopeCase(file: .ledger, keyID: 0xDEAD_BEEF, plaintext: Data("[]".utf8),
                     hex: "544c595601040000deadbeefa0a1a2a3a4a5a6a7a8a9aaabbd4553b61004cf09e59368bc4cf35293bda3"),
    ]

    @Test("envelope known answers", arguments: envelopeCases)
    func envelopeKnownAnswer(_ testCase: EnvelopeCase) throws {
        let header = SealedBlobHeader(file: testCase.file, keyID: testCase.keyID)
        let sealed = try SealedBlob.seal(testCase.plaintext, header: header, key: key, nonce: AES.GCM.Nonce(data: nonce))
        #expect(sealed.hex == testCase.hex)
        let opened = try SealedBlob.open(Data(hex: testCase.hex), key: key)
        #expect(opened.header == header)
        #expect(opened.plaintext == testCase.plaintext)
    }

    @Test func negativeVectors() {
        let blob = Data(hex: Self.tv1)

        var tagFlip = blob; tagFlip[tagFlip.count - 1] ^= 0x01
        #expect(throws: VaultError.authenticationFailed) { try SealedBlob.open(tagFlip, key: key) }

        var fileByte = blob; fileByte[5] = 0x02 // AAD
        #expect(throws: VaultError.authenticationFailed) { try SealedBlob.open(fileByte, key: key) }

        var keyIDByte = blob; keyIDByte[11] = 0x02 // AAD
        #expect(throws: VaultError.authenticationFailed) { try SealedBlob.open(keyIDByte, key: key) }

        #expect(throws: VaultError.malformed) { try SealedBlob.open(blob.prefix(39), key: key) }

        var badMagic = blob; badMagic[0] = 0x58
        #expect(throws: VaultError.malformed) { try SealedBlob.open(badMagic, key: key) }

        var badFormat = blob; badFormat[4] = 0x02
        #expect(throws: VaultError.unsupportedFormat(2)) { try SealedBlob.open(badFormat, key: key) }

        var badFlags = blob; badFlags[7] = 0x01
        #expect(throws: VaultError.unsupportedFormat(1)) { try SealedBlob.open(badFlags, key: key) }

        #expect(throws: VaultError.authenticationFailed) {
            try SealedBlob.open(blob, key: SymmetricKey(data: Data(count: 32)))
        }
    }

    @Test func randomNoncesNeverRepeat() throws {
        let header = SealedBlobHeader(file: .snapshot, keyID: 1)
        let nonces = try Set((0..<1_000).map { _ in
            try SealedBlob.seal(Data("same".utf8), header: header, key: key).subdata(in: 12..<24)
        })
        #expect(nonces.count == 1_000)
    }
}

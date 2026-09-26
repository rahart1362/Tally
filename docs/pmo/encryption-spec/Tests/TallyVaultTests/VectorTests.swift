#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import XCTest
@testable import TallyVault

/// Known answers computed independently with python-cryptography 50.0.1 (OpenSSL 4.0.2).
/// TC16 = McGrew & Viega GCM spec, Test Case 16 (AES-256, 96-bit IV, with AAD).
final class VectorTests: XCTestCase {
    let key = SymmetricKey(data: Data((0..<32).map { UInt8($0) }))
    let nonce = Data((0xa0...0xab).map { UInt8($0) })
    static let tv1 = "544c59560101000000000001a0a1a2a3a4a5a6a7a8a9aaab9d3a0a0f7ffa7facb577066bd84fc946655a49e313646e"

    func testPrimitiveMatchesGCMSpecTestCase16() throws {
        let box = try AES.GCM.seal(
            Data(hex: "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39"),
            using: SymmetricKey(data: Data(hex: "feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308")),
            nonce: try AES.GCM.Nonce(data: Data(hex: "cafebabefacedbaddecaf888")),
            authenticating: Data(hex: "feedfacedeadbeeffeedfacedeadbeefabaddad2"))
        XCTAssertEqual(box.ciphertext.hex, "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662")
        XCTAssertEqual(box.tag.hex, "76fc6ece0f4e1768cddf8853bb2d551b")
    }

    func testEnvelopeKnownAnswers() throws {
        let cases: [(StoreFile, UInt32, Data, String)] = [
            (.snapshot, 1, Data(#"{"v":1}"#.utf8), Self.tv1),
            (.snapshot, 1, Data(), "544c59560101000000000001a0a1a2a3a4a5a6a7a8a9aaab77dd7c44b89e4d75d3af373e7244d192"),
            (.glance, 7, Data("Due: MATH 221 \u{2013} Problem Set 4".utf8),
             "544c59560102000000000007a0a1a2a3a4a5a6a7a8a9aaaba26d1917658643eb2a45b5e1365a225ee38c0962fdd52e09f12e75e30b8b41a3e8788465b76b6f094732287b312360"),
            (.ledger, 0xDEADBEEF, Data("[]".utf8), "544c595601040000deadbeefa0a1a2a3a4a5a6a7a8a9aaabbd4553b61004cf09e59368bc4cf35293bda3"),
        ]
        for (file, keyID, plaintext, expected) in cases {
            let header = SealedBlobHeader(file: file, keyID: keyID)
            XCTAssertEqual(try SealedBlob.seal(plaintext, header: header, key: key, nonce: AES.GCM.Nonce(data: nonce)).hex, expected)
            let opened = try SealedBlob.open(Data(hex: expected), key: key)
            XCTAssertEqual(opened.header, header); XCTAssertEqual(opened.plaintext, plaintext)
        }
    }

    func testNegativeVectors() {
        let blob = Data(hex: Self.tv1)
        func expect(_ b: Data, key k: SymmetricKey? = nil, _ err: VaultError, line: UInt = #line) {
            XCTAssertThrowsError(try SealedBlob.open(b, key: k ?? key), line: line) { XCTAssertEqual($0 as? VaultError, err, line: line) }
        }
        var n1 = blob; n1[n1.count - 1] ^= 0x01; expect(n1, .authenticationFailed)          // tag bit flip
        var n2 = blob; n2[5] = 0x02;             expect(n2, .authenticationFailed)          // file byte (AAD)
        var n3 = blob; n3[11] = 0x02;            expect(n3, .authenticationFailed)          // keyID (AAD)
        expect(blob.prefix(39), .malformed)                                                  // truncated
        var n5 = blob; n5[0] = 0x58;             expect(n5, .malformed)                     // magic
        var n6 = blob; n6[4] = 0x02;             expect(n6, .unsupportedFormat(2))          // format
        var n7 = blob; n7[7] = 0x01;             expect(n7, .unsupportedFormat(1))          // reserved flags
        expect(blob, key: SymmetricKey(data: Data(count: 32)), .authenticationFailed)       // wrong key
    }

    func testRandomNoncesNeverRepeat() throws {
        let header = SealedBlobHeader(file: .snapshot, keyID: 1)
        let nonces = try Set((0..<1_000).map { _ in try SealedBlob.seal(Data("same".utf8), header: header, key: key).subdata(in: 12..<24) })
        XCTAssertEqual(nonces.count, 1_000)
    }
}

import Foundation
import Testing
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
@testable import TallyCanvasAPI

@Suite("Signed institution registry: format, verifier and bundled fallback (WP-SEC-12)")
struct InstitutionRegistryTests {
    // Every test generates its own ephemeral key — a real signing key is never committed
    // (WP-SEC-12 "the signing key never enters the repo or CI").
    private let privateKey = P256.Signing.PrivateKey()
    private var publicKey: P256.Signing.PublicKey { privateKey.publicKey }
    private let now = Date(timeIntervalSince1970: 1_790_600_400)
    private let appVersion = SemanticVersion(major: 2, minor: 0, patch: 0)

    private func registry(version: Int = 1, minAppVersion: String = "1.0.0",
                         issuedAt: Date? = nil, expiresAt: Date? = nil) -> SignedInstitutionRegistry {
        SignedInstitutionRegistry(
            version: version, issuedAt: issuedAt ?? now, expiresAt: expiresAt ?? now.addingTimeInterval(30 * 24 * 3600),
            minAppVersion: minAppVersion,
            entries: [
                InstitutionRegistryEntry(host: "canvas.northfield.example", clientID: "client-1", clientType: .publicPKCE, familyCapable: true),
                InstitutionRegistryEntry(host: "canvas.northgate.example", clientID: "client-2", clientType: .publicPKCE, familyCapable: false),
            ])
    }

    private func signedData(_ registry: SignedInstitutionRegistry, key: P256.Signing.PrivateKey? = nil) throws -> Data {
        try InstitutionRegistrySigner.encode(try InstitutionRegistrySigner.sign(registry, privateKey: key ?? privateKey))
    }

    // MARK: - Happy path

    @Test func verifiesARoundTrippedRegistry() throws {
        let data = try signedData(registry())
        let verified = try InstitutionRegistryVerifier.verify(data, publicKey: publicKey, now: now, currentAppVersion: appVersion)
        #expect(verified.entries.count == 2)
        #expect(verified.entries[0].host == "canvas.northfield.example")
        #expect(verified.entries[0].familyCapable)
        #expect(!verified.entries[1].familyCapable)
    }

    @Test func integratesWithClientRegistryViaTheNewInitializer() throws {
        let data = try signedData(registry())
        let verified = try InstitutionRegistryVerifier.verify(data, publicKey: publicKey, now: now, currentAppVersion: appVersion)
        let clientRegistry = ClientRegistry(verified)
        #expect(clientRegistry.count == 2)
        #expect(clientRegistry.registration(for: "canvas.northfield.example")?.familyCapable == true)
        #expect(clientRegistry.registration(for: "canvas.northgate.example")?.clientType == .publicPKCE)
    }

    // MARK: - Rejections (WP-SEC-12 acceptance criteria)

    @Test func rejectsATamperedPayload() throws {
        let envelope = try InstitutionRegistrySigner.sign(registry(), privateKey: privateKey)
        var tamperedPayload = envelope.payload
        // Flip one byte in the middle of the JSON, keeping it the same length.
        let flipIndex = tamperedPayload.index(tamperedPayload.startIndex, offsetBy: tamperedPayload.count / 2)
        tamperedPayload[flipIndex] ^= 0xFF
        let tampered = try InstitutionRegistryCodec.encoder().encode(
            InstitutionRegistryEnvelope(payload: tamperedPayload, signature: envelope.signature))
        #expect(throws: InstitutionRegistryError.badSignature) {
            _ = try InstitutionRegistryVerifier.verify(tampered, publicKey: publicKey, now: now, currentAppVersion: appVersion)
        }
    }

    @Test func rejectsASignatureFromTheWrongKey() throws {
        let otherKey = P256.Signing.PrivateKey()
        let data = try signedData(registry(), key: otherKey)
        #expect(throws: InstitutionRegistryError.badSignature) {
            _ = try InstitutionRegistryVerifier.verify(data, publicKey: publicKey, now: now, currentAppVersion: appVersion)
        }
    }

    @Test func rejectsARollbackToAnOlderOrEqualVersion() throws {
        let data = try signedData(registry(version: 3))
        #expect(throws: InstitutionRegistryError.rollback(cached: 3, incoming: 3)) {
            _ = try InstitutionRegistryVerifier.verify(data, publicKey: publicKey, now: now, cachedVersion: 3, currentAppVersion: appVersion)
        }
        let older = try signedData(registry(version: 2))
        #expect(throws: InstitutionRegistryError.rollback(cached: 3, incoming: 2)) {
            _ = try InstitutionRegistryVerifier.verify(older, publicKey: publicKey, now: now, cachedVersion: 3, currentAppVersion: appVersion)
        }
    }

    @Test func acceptsAStrictlyNewerVersion() throws {
        let data = try signedData(registry(version: 4))
        let verified = try InstitutionRegistryVerifier.verify(data, publicKey: publicKey, now: now, cachedVersion: 3, currentAppVersion: appVersion)
        #expect(verified.version == 4)
    }

    @Test func rejectsAnExpiredRegistry() throws {
        let data = try signedData(registry(expiresAt: now.addingTimeInterval(-1)))
        #expect(throws: InstitutionRegistryError.expired(expiresAt: now.addingTimeInterval(-1))) {
            _ = try InstitutionRegistryVerifier.verify(data, publicKey: publicKey, now: now, currentAppVersion: appVersion)
        }
    }

    @Test func rejectsAnAppOlderThanMinAppVersion() throws {
        let data = try signedData(registry(minAppVersion: "9.0.0"))
        #expect(throws: InstitutionRegistryError.appTooOld(required: SemanticVersion(major: 9, minor: 0, patch: 0), current: appVersion)) {
            _ = try InstitutionRegistryVerifier.verify(data, publicKey: publicKey, now: now, currentAppVersion: appVersion)
        }
    }

    @Test func rejectsMalformedEnvelopeBytes() {
        #expect(throws: InstitutionRegistryError.malformed) {
            _ = try InstitutionRegistryVerifier.verify(Data("not json".utf8), publicKey: publicKey, now: now, currentAppVersion: appVersion)
        }
    }

    // MARK: - Bundled fallback

    @Test func fallsBackToTheBundledCopyWhenTheFetchedOneIsTamperedRolledBackOrExpired() throws {
        let bundled = try signedData(registry(version: 1))
        let tamperedFetch = Data("garbage".utf8)
        let loaded = try InstitutionRegistryLoader.load(
            fetched: tamperedFetch, bundled: bundled, publicKey: publicKey, now: now, cachedVersion: nil, currentAppVersion: appVersion)
        #expect(loaded.usedBundledFallback)
        #expect(loaded.registry.version == 1)
    }

    @Test func prefersTheFetchedCopyWhenItVerifies() throws {
        let bundled = try signedData(registry(version: 1))
        let fetched = try signedData(registry(version: 2))
        let loaded = try InstitutionRegistryLoader.load(
            fetched: fetched, bundled: bundled, publicKey: publicKey, now: now, cachedVersion: 1, currentAppVersion: appVersion)
        #expect(!loaded.usedBundledFallback)
        #expect(loaded.registry.version == 2)
    }

    @Test func fallsBackWhenNoFetchedCopyIsAvailable() throws {
        let bundled = try signedData(registry(version: 1))
        let loaded = try InstitutionRegistryLoader.load(
            fetched: nil, bundled: bundled, publicKey: publicKey, now: now, cachedVersion: nil, currentAppVersion: appVersion)
        #expect(loaded.usedBundledFallback)
    }

    @Test func aStaleBundledCopyStillLoadsPastItsOwnExpiry() throws {
        // The bundled copy shipped a long time ago and the device has never fetched a
        // replacement: it must still work rather than leaving the student with nothing.
        let staleBundled = try signedData(registry(version: 1, expiresAt: now.addingTimeInterval(-999_999)))
        let loaded = try InstitutionRegistryLoader.load(
            fetched: nil, bundled: staleBundled, publicKey: publicKey, now: now, cachedVersion: 5, currentAppVersion: appVersion)
        #expect(loaded.usedBundledFallback)
        #expect(loaded.registry.version == 1) // not rejected as a "rollback" against cachedVersion 5, either
    }

    @Test func throwsWhenEvenTheBundledCopyFailsToVerify() {
        let corruptBundled = Data("not signed at all".utf8)
        #expect(throws: InstitutionRegistryError.malformed) {
            _ = try InstitutionRegistryLoader.load(
                fetched: nil, bundled: corruptBundled, publicKey: publicKey, now: now, cachedVersion: nil, currentAppVersion: appVersion)
        }
    }

    // MARK: - SemanticVersion

    @Test(arguments: [
        ("1.2.3", SemanticVersion(major: 1, minor: 2, patch: 3)),
        ("2", SemanticVersion(major: 2, minor: 0, patch: 0)),
        ("1.4", SemanticVersion(major: 1, minor: 4, patch: 0)),
        ("1.2.3-beta.1", SemanticVersion(major: 1, minor: 2, patch: 3)),
    ] as [(String, SemanticVersion?)])
    func parsesDottedVersions(_ text: String, _ expected: SemanticVersion?) {
        #expect(SemanticVersion(text) == expected)
    }

    @Test(arguments: ["", "a.b.c", "1.2.3.4"])
    func rejectsMalformedVersions(_ text: String) {
        #expect(SemanticVersion(text) == nil)
    }

    @Test func comparesBySemver() {
        #expect(SemanticVersion(major: 1, minor: 9, patch: 9) < SemanticVersion(major: 2, minor: 0, patch: 0))
        #expect(SemanticVersion(major: 2, minor: 0, patch: 0) >= SemanticVersion(major: 2, minor: 0, patch: 0))
    }
}

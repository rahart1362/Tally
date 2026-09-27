import Foundation
import Testing
import TallyTestSupport
@testable import TallyStore

/// `VaultKeyring`/`VaultSealer` on their own, with no file I/O (that's `VaultSealerAndFileAccessTests`,
/// WP-ENC-02). Ported from `docs/pmo/encryption-spec`'s `SealerAndStoreTests` unchanged in meaning.
@Suite("VaultKeyring and VaultSealer")
struct VaultKeyringTests {
    let account = "a1b2c3d4"
    let payload = Data(#"{"courses":["MATH 221","CHEM 110"]}"#.utf8)

    private func scope(_ audience: KeyAudience, account: String = "a1b2c3d4") -> KeyScope {
        KeyScope(account: account, audience: audience)
    }

    @Test func sealOpenRoundTrips() throws {
        let keys = InMemoryVaultKeyStore()
        let sealer = VaultSealer(account: account, keyring: VaultKeyring(store: keys), mayCreateKeys: true)
        let sealed = try sealer.seal(payload, file: .snapshot)
        #expect(try sealer.open(sealed, file: .snapshot) == payload)
    }

    @Test func openingAsTheWrongSlotIsRejected() throws {
        let keys = InMemoryVaultKeyStore()
        let sealer = VaultSealer(account: account, keyring: VaultKeyring(store: keys), mayCreateKeys: true)
        let sealed = try sealer.seal(payload, file: .ledger)
        #expect(throws: VaultError.fileMismatch) { try sealer.open(sealed, file: .snapshot) }
    }

    @Test func freshKeyringCannotOpenAnEarlierBlob() throws {
        let keys = InMemoryVaultKeyStore()
        let sealer = VaultSealer(account: account, keyring: VaultKeyring(store: keys), mayCreateKeys: true)
        let sealed = try sealer.seal(payload, file: .snapshot)
        let freshSealer = VaultSealer(account: account, keyring: VaultKeyring(store: InMemoryVaultKeyStore()), mayCreateKeys: true)
        #expect(throws: VaultError.keyMissing) { try freshSealer.open(sealed, file: .snapshot) }
    }

    @Test func readOnlyProcessNeverMintsAKey() throws {
        let keys = InMemoryVaultKeyStore()
        let sealer = VaultSealer(account: account, keyring: VaultKeyring(store: keys), mayCreateKeys: false)
        #expect(throws: VaultError.readOnlyProcess) { try sealer.seal(payload, file: .glance) }
        #expect(keys.count(scope(.widget)) == 0)
    }

    @Test func concurrentFirstSealsMintExactlyOneKeyPerScope() async throws {
        let keys = InMemoryVaultKeyStore()
        let ring = VaultKeyring(store: keys)
        let sealer = VaultSealer(account: account, keyring: ring, mayCreateKeys: true)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<64 {
                group.addTask { _ = try? sealer.seal(self.payload, file: i.isMultiple(of: 2) ? .snapshot : .ledger) }
            }
        }
        #expect(keys.count(scope(.app)) == 1)
    }

    @Test func shredRemovesBothAudiencesForOneAccountOnly() throws {
        let keys = InMemoryVaultKeyStore()
        let ring = VaultKeyring(store: keys)
        _ = try ring.currentKey(for: scope(.app), createIfMissing: true)
        _ = try ring.currentKey(for: scope(.widget), createIfMissing: true)
        _ = try ring.currentKey(for: scope(.app, account: "other"), createIfMissing: true)
        try ring.shred(account: account)
        #expect(keys.count(scope(.app)) == 0)
        #expect(keys.count(scope(.widget)) == 0)
        #expect(keys.count(scope(.app, account: "other")) == 1)
    }

    @Test(arguments: StoreFile.allCases)
    func dispositionTable(_ file: StoreFile) {
        #expect(VaultError.protectedDataUnavailable.disposition(for: file) == .retryAfterUnlock)
        #expect(VaultError.storage(code: 1).disposition(for: file) == .keepAndReport)
        for e in [VaultError.keyMissing, .malformed, .unsupportedFormat(9), .fileMismatch, .authenticationFailed] {
            #expect(e.disposition(for: file) == (file == .userState ? .resetUserStateAndTell : .discardAndRebuild))
        }
    }
}

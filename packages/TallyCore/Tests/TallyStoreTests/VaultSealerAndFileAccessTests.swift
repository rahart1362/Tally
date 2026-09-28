import Foundation
import Testing
import TallyTestSupport
@testable import TallyStore

/// Test double for `SnapshotSealer` that injects a failure on open (exercises `.keepAndReport`).
private struct FailingSealer: SnapshotSealer {
    let error: VaultError
    func seal(_ plaintext: Data, file: StoreFile) throws -> Data { plaintext }
    func open(_ sealed: Data, file: StoreFile) throws -> Data { throw error }
}

private func tempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
    try ProtectedFile.prepareDirectory(url, excludeFromBackup: true)
    return url
}

/// `ProtectedFile` + `SealedFileAccess` + the orphaned-temp sweep, exercised end to end (WP-ENC-02).
/// Ported from `docs/pmo/encryption-spec`'s `SealerAndStoreTests` unchanged in meaning.
@Suite("SealedFileAccess: protected atomic reads and writes")
struct VaultSealerAndFileAccessTests {
    let account = "a1b2c3d4"
    let payload = Data(#"{"courses":["MATH 221","CHEM 110"]}"#.utf8)

    private func makeAccess(_ keys: InMemoryVaultKeyStore, isOwner: Bool = true) -> SealedFileAccess {
        SealedFileAccess(sealer: VaultSealer(account: account, keyring: VaultKeyring(store: keys), mayCreateKeys: isOwner), isOwner: isOwner)
    }

    private func scope(_ audience: KeyAudience, account: String) -> KeyScope { KeyScope(account: account, audience: audience) }

    @Test func absentFileReadsAsAbsent() throws {
        let dir = try tempDir()
        let access = makeAccess(InMemoryVaultKeyStore())
        #expect(access.read(.snapshot, at: dir.appendingPathComponent("snapshot.sealed")) == .absent)
    }

    @Test func roundTripAtomicReplaceNoTempFilesOneKeyPerScope() throws {
        let dir = try tempDir()
        let keys = InMemoryVaultKeyStore()
        let access = makeAccess(keys)
        let snapshotURL = dir.appendingPathComponent("snapshot.sealed")
        let ledgerURL = dir.appendingPathComponent("ledger.sealed")

        try access.write(payload, .snapshot, to: snapshotURL, excludeFromBackup: true)
        try access.write(payload + Data("x".utf8), .snapshot, to: snapshotURL, excludeFromBackup: true)
        try access.write(payload, .ledger, to: ledgerURL, excludeFromBackup: true)

        #expect(access.read(.snapshot, at: snapshotURL) == .plaintext(payload + Data("x".utf8)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["ledger.sealed", "snapshot.sealed"])
        #expect(keys.count(scope(.app, account: account)) == 1, "snapshot and ledger share the account's app key")
    }

    @Test func ciphertextOnDiskContainsNoPlaintext() throws {
        let dir = try tempDir()
        let access = makeAccess(InMemoryVaultKeyStore())
        let url = dir.appendingPathComponent("snapshot.sealed")
        try access.write(payload, .snapshot, to: url, excludeFromBackup: true)
        #expect(try Data(contentsOf: url).range(of: Data("MATH 221".utf8)) == nil)
    }

    @Test func newDeviceKeyMissingDiscardsRederivableFile() throws {
        let dir = try tempDir()
        let url = dir.appendingPathComponent("snapshot.sealed")
        try makeAccess(InMemoryVaultKeyStore()).write(payload, .snapshot, to: url, excludeFromBackup: true)
        let restored = makeAccess(InMemoryVaultKeyStore()) // a fresh keyring: models a new device / reinstall
        #expect(restored.read(.snapshot, at: url) == .failed(.keyMissing, .discardAndRebuild))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func userStateFailureIsResetAndToldNotSilentlyRebuilt() throws {
        let dir = try tempDir()
        let keys = InMemoryVaultKeyStore()
        let ring = VaultKeyring(store: keys)
        let access = SealedFileAccess(sealer: VaultSealer(account: account, keyring: ring, mayCreateKeys: true), isOwner: true)
        let url = dir.appendingPathComponent("user-state.sealed")
        try access.write(payload, .userState, to: url, excludeFromBackup: false)
        try ring.shred(account: account)
        #expect(access.read(.userState, at: url) == .failed(.keyMissing, .resetUserStateAndTell))
    }

    @Test func tamperedBlobIsDiscarded() throws {
        let dir = try tempDir()
        let access = makeAccess(InMemoryVaultKeyStore())
        let url = dir.appendingPathComponent("snapshot.sealed")
        try access.write(payload, .snapshot, to: url, excludeFromBackup: true)
        var raw = try Data(contentsOf: url)
        raw[raw.count / 2] ^= 0xFF
        try raw.write(to: url)
        #expect(access.read(.snapshot, at: url) == .failed(.authenticationFailed, .discardAndRebuild))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func blobCopiedIntoAnotherSlotIsRejected() throws {
        let dir = try tempDir()
        let access = makeAccess(InMemoryVaultKeyStore())
        let ledgerURL = dir.appendingPathComponent("ledger.sealed")
        let snapshotURL = dir.appendingPathComponent("snapshot.sealed")
        try access.write(payload, .ledger, to: ledgerURL, excludeFromBackup: true)
        try FileManager.default.copyItem(at: ledgerURL, to: snapshotURL)
        #expect(access.read(.snapshot, at: snapshotURL) == .failed(.fileMismatch, .discardAndRebuild))
    }

    /// Regression guard for the field-reported failure (encryption.md ENC-01/ENC-02): a locked
    /// background launch must not be mistaken for corruption and must not wipe the store or mint
    /// a new key.
    @Test func lockedKeychainIsRetryAfterUnlockAndDestroysNothing() throws {
        let dir = try tempDir()
        let keys = InMemoryVaultKeyStore()
        let access = makeAccess(keys)
        let url = dir.appendingPathComponent("snapshot.sealed")
        try access.write(payload, .snapshot, to: url, excludeFromBackup: true)

        keys.failure = .protectedDataUnavailable
        #expect(access.read(.snapshot, at: url) == .failed(.protectedDataUnavailable, .retryAfterUnlock))
        #expect(throws: VaultError.protectedDataUnavailable) { try access.write(payload, .snapshot, to: url, excludeFromBackup: true) }
        keys.failure = nil

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(keys.count(scope(.app, account: account)) == 1)
        #expect(access.read(.snapshot, at: url) == .plaintext(payload))
    }

    @Test func unclassifiedErrorKeepsFile() throws {
        let dir = try tempDir()
        let access = makeAccess(InMemoryVaultKeyStore())
        let url = dir.appendingPathComponent("snapshot.sealed")
        try access.write(payload, .snapshot, to: url, excludeFromBackup: true)
        let flaky = SealedFileAccess(sealer: FailingSealer(error: .storage(code: 5)), isOwner: true)
        #expect(flaky.read(.snapshot, at: url) == .failed(.storage(code: 5), .keepAndReport))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func widgetCanOpenGlanceOnlyAndNeverWritesOrDeletes() throws {
        let dir = try tempDir()
        let keys = InMemoryVaultKeyStore()
        let access = makeAccess(keys)
        let glanceURL = dir.appendingPathComponent("glance.sealed")
        let snapshotURL = dir.appendingPathComponent("snapshot.sealed")
        try access.write(payload, .glance, to: glanceURL, excludeFromBackup: true)
        try access.write(payload, .snapshot, to: snapshotURL, excludeFromBackup: true)

        let widgetRing = VaultKeyring(store: keys.view(visible: [.widget])) // App Group access group only
        let widget = SealedFileAccess(sealer: VaultSealer(account: account, keyring: widgetRing, mayCreateKeys: false), isOwner: false)
        #expect(widget.read(.glance, at: glanceURL) == .plaintext(payload))
        #expect(widget.read(.snapshot, at: snapshotURL) == .failed(.keyMissing, .discardAndRebuild))
        #expect(FileManager.default.fileExists(atPath: snapshotURL.path), "non-owner must never delete")
        #expect(throws: VaultError.readOnlyProcess) { try widget.write(payload, .glance, to: glanceURL, excludeFromBackup: true) }
    }

    @Test func purgeIsCryptographicEvenIfCiphertextSurvives() throws {
        var dir = try tempDir()
        let keys = InMemoryVaultKeyStore()
        let ring = VaultKeyring(store: keys)
        let access = SealedFileAccess(sealer: VaultSealer(account: account, keyring: ring, mayCreateKeys: true), isOwner: true)
        let url = dir.appendingPathComponent("snapshot.sealed")
        try access.write(payload, .snapshot, to: url, excludeFromBackup: true)
        let leftover = try Data(contentsOf: url) // e.g. a backup copy taken before the purge

        try VaultPurger.purge(account: account, keyring: ring, directories: [dir])
        #expect(keys.count(scope(.app, account: account)) + keys.count(scope(.widget, account: account)) == 0)
        #expect(!FileManager.default.fileExists(atPath: dir.path))

        dir = try tempDir()
        let newURL = dir.appendingPathComponent("snapshot.sealed")
        try access.write(Data("new".utf8), .snapshot, to: newURL, excludeFromBackup: true) // new random key ID
        try leftover.write(to: newURL)
        #expect(access.read(.snapshot, at: newURL) == .failed(.keyMissing, .discardAndRebuild))
    }

    @Test func purgeOneAccountLeavesOtherAccountReadable() throws {
        let dir = try tempDir()
        let keys = InMemoryVaultKeyStore()
        let ring = VaultKeyring(store: keys)
        let url = dir.appendingPathComponent("snapshot.sealed")
        let other = SealedFileAccess(sealer: VaultSealer(account: "ffff0000", keyring: ring, mayCreateKeys: true), isOwner: true)
        try other.write(payload, .snapshot, to: url, excludeFromBackup: true)
        try ring.shred(account: account)
        #expect(other.read(.snapshot, at: url) == .plaintext(payload))
    }

    @Test func reinstallWithSurvivingKeychainShredsInheritedKeys() throws {
        let dir = try tempDir()
        let keys = InMemoryVaultKeyStore()
        let ring = VaultKeyring(store: keys)
        let access = SealedFileAccess(sealer: VaultSealer(account: account, keyring: ring, mayCreateKeys: true), isOwner: true)
        let url = dir.appendingPathComponent("snapshot.sealed")
        let sentinel = dir.appendingPathComponent(".installed")

        try access.write(payload, .snapshot, to: url, excludeFromBackup: true)
        try VaultBootstrap.reconcileInstall(keyring: ring, sentinel: sentinel) // first launch of this install
        #expect(keys.count(scope(.app, account: account)) == 0)

        try access.write(payload, .snapshot, to: url, excludeFromBackup: true)
        try VaultBootstrap.reconcileInstall(keyring: ring, sentinel: sentinel) // later launches: no-op
        #expect(keys.count(scope(.app, account: account)) == 1)
    }

    @Test func sweepRemovesOrphanedTempFilesOnly() throws {
        let dir = try tempDir()
        let access = makeAccess(InMemoryVaultKeyStore())
        let url = dir.appendingPathComponent("snapshot.sealed")
        try access.write(payload, .snapshot, to: url, excludeFromBackup: true)
        try Data("junk".utf8).write(to: dir.appendingPathComponent(".snapshot.sealed.tmp123"))
        ProtectedFile.sweep(directory: dir, keeping: ["snapshot.sealed"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["snapshot.sealed"])
    }
}

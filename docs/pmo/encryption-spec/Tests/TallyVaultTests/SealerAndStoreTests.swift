import Foundation
import XCTest
@testable import TallyVault

final class SealerAndStoreTests: XCTestCase {
    let account = "a1b2c3d4"
    var keys: InMemoryKeyStore!
    var ring: VaultKeyring!
    var dir: URL!
    var app: SealedFileAccess!
    let payload = Data(#"{"courses":["MATH 221","CHEM 110"]}"#.utf8)

    override func setUpWithError() throws {
        keys = InMemoryKeyStore(); ring = VaultKeyring(store: keys); dir = try tempDir()
        app = SealedFileAccess(sealer: VaultSealer(account: account, keyring: ring, mayCreateKeys: true), isOwner: true)
    }
    func url(_ f: StoreFile) -> URL { dir.appendingPathComponent("\(f).sealed") }
    func exists(_ f: StoreFile) -> Bool { FileManager.default.fileExists(atPath: url(f).path) }
    func scope(_ a: KeyAudience) -> KeyScope { KeyScope(account: account, audience: a) }

    func testAbsentFileReadsAsAbsent() { XCTAssertEqual(app.read(.snapshot, at: url(.snapshot)), .absent) }

    func testRoundTripAtomicReplaceNoTempFilesOneKeyPerScope() throws {
        try app.write(payload, .snapshot, to: url(.snapshot), excludeFromBackup: true)
        try app.write(payload + Data("x".utf8), .snapshot, to: url(.snapshot), excludeFromBackup: true)
        try app.write(payload, .ledger, to: url(.ledger), excludeFromBackup: true)
        XCTAssertEqual(app.read(.snapshot, at: url(.snapshot)), .plaintext(payload + Data("x".utf8)))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), ["ledger.sealed", "snapshot.sealed"])
        XCTAssertEqual(keys.count(scope(.app)), 1, "snapshot and ledger share the account's app key")
    }

    func testCiphertextOnDiskContainsNoPlaintext() throws {
        try app.write(payload, .snapshot, to: url(.snapshot), excludeFromBackup: true)
        XCTAssertNil(try Data(contentsOf: url(.snapshot)).range(of: Data("MATH 221".utf8)))
    }

    func testNewDeviceKeyMissingDiscardsRederivableFile() throws {
        try app.write(payload, .snapshot, to: url(.snapshot), excludeFromBackup: true)
        let restored = SealedFileAccess(sealer: VaultSealer(account: account, keyring: VaultKeyring(store: InMemoryKeyStore()), mayCreateKeys: true), isOwner: true)
        XCTAssertEqual(restored.read(.snapshot, at: url(.snapshot)), .failed(.keyMissing, .discardAndRebuild))
        XCTAssertFalse(exists(.snapshot))
    }

    func testUserStateFailureIsResetAndToldNotSilentlyRebuilt() throws {
        try app.write(payload, .userState, to: url(.userState), excludeFromBackup: false)
        try ring.shred(account: account)
        XCTAssertEqual(app.read(.userState, at: url(.userState)), .failed(.keyMissing, .resetUserStateAndTell))
    }

    func testTamperedBlobIsDiscarded() throws {
        try app.write(payload, .snapshot, to: url(.snapshot), excludeFromBackup: true)
        var raw = try Data(contentsOf: url(.snapshot)); raw[raw.count / 2] ^= 0xFF
        try raw.write(to: url(.snapshot))
        XCTAssertEqual(app.read(.snapshot, at: url(.snapshot)), .failed(.authenticationFailed, .discardAndRebuild))
        XCTAssertFalse(exists(.snapshot))
    }

    func testBlobCopiedIntoAnotherSlotIsRejected() throws {
        try app.write(payload, .ledger, to: url(.ledger), excludeFromBackup: true)
        try FileManager.default.copyItem(at: url(.ledger), to: url(.snapshot))
        XCTAssertEqual(app.read(.snapshot, at: url(.snapshot)), .failed(.fileMismatch, .discardAndRebuild))
    }

    /// Regression guard for the field-reported failure: a locked background launch must not be
    /// mistaken for corruption and wipe the store or mint a new key.
    func testLockedKeychainIsRetryAfterUnlockAndDestroysNothing() throws {
        try app.write(payload, .snapshot, to: url(.snapshot), excludeFromBackup: true)
        keys.failure = .protectedDataUnavailable
        XCTAssertEqual(app.read(.snapshot, at: url(.snapshot)), .failed(.protectedDataUnavailable, .retryAfterUnlock))
        XCTAssertThrowsError(try app.write(payload, .snapshot, to: url(.snapshot), excludeFromBackup: true))
        keys.failure = nil
        XCTAssertTrue(exists(.snapshot)); XCTAssertEqual(keys.count(scope(.app)), 1)
        XCTAssertEqual(app.read(.snapshot, at: url(.snapshot)), .plaintext(payload))
    }

    func testUnclassifiedErrorKeepsFile() throws {
        try app.write(payload, .snapshot, to: url(.snapshot), excludeFromBackup: true)
        let flaky = SealedFileAccess(sealer: FailingSealer(error: .storage(code: 5)), isOwner: true)
        XCTAssertEqual(flaky.read(.snapshot, at: url(.snapshot)), .failed(.storage(code: 5), .keepAndReport))
        XCTAssertTrue(exists(.snapshot))
    }

    func testWidgetCanOpenGlanceOnlyAndNeverWritesOrDeletes() throws {
        try app.write(payload, .glance, to: url(.glance), excludeFromBackup: true)
        try app.write(payload, .snapshot, to: url(.snapshot), excludeFromBackup: true)
        let widgetRing = VaultKeyring(store: keys.view(visible: [.widget]))  // App Group access group only
        let widget = SealedFileAccess(sealer: VaultSealer(account: account, keyring: widgetRing, mayCreateKeys: false), isOwner: false)
        XCTAssertEqual(widget.read(.glance, at: url(.glance)), .plaintext(payload))
        XCTAssertEqual(widget.read(.snapshot, at: url(.snapshot)), .failed(.keyMissing, .discardAndRebuild))
        XCTAssertTrue(exists(.snapshot), "non-owner must never delete")
        XCTAssertThrowsError(try widget.write(payload, .glance, to: url(.glance), excludeFromBackup: true))
    }

    func testConcurrentFirstSealsMintExactlyOneKeyPerScope() throws {
        let sealer = VaultSealer(account: account, keyring: ring, mayCreateKeys: true), payload = self.payload
        DispatchQueue.concurrentPerform(iterations: 64) { i in
            _ = try? sealer.seal(payload, file: i.isMultiple(of: 2) ? .snapshot : .ledger)
        }
        XCTAssertEqual(keys.count(scope(.app)), 1)
    }

    func testPurgeIsCryptographicEvenIfCiphertextSurvives() throws {
        try app.write(payload, .snapshot, to: url(.snapshot), excludeFromBackup: true)
        let leftover = try Data(contentsOf: url(.snapshot))               // e.g. a backup copy
        try VaultPurger.purge(account: account, keyring: ring, directories: [dir])
        XCTAssertEqual(keys.count(scope(.app)) + keys.count(scope(.widget)), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        dir = try tempDir()
        try app.write(Data("new".utf8), .snapshot, to: url(.snapshot), excludeFromBackup: true) // new random key id
        try leftover.write(to: url(.snapshot))
        XCTAssertEqual(app.read(.snapshot, at: url(.snapshot)), .failed(.keyMissing, .discardAndRebuild))
    }

    func testPurgeOneAccountLeavesOtherAccountReadable() throws {
        let other = SealedFileAccess(sealer: VaultSealer(account: "ffff0000", keyring: ring, mayCreateKeys: true), isOwner: true)
        try other.write(payload, .snapshot, to: url(.snapshot), excludeFromBackup: true)
        try ring.shred(account: account)
        XCTAssertEqual(other.read(.snapshot, at: url(.snapshot)), .plaintext(payload))
    }

    func testReinstallWithSurvivingKeychainShredsInheritedKeys() throws {
        try app.write(payload, .snapshot, to: url(.snapshot), excludeFromBackup: true)
        let sentinel = dir.appendingPathComponent(".installed")
        try VaultBootstrap.reconcileInstall(keyring: ring, sentinel: sentinel)      // first launch of this install
        XCTAssertEqual(keys.count(scope(.app)), 0)
        try app.write(payload, .snapshot, to: url(.snapshot), excludeFromBackup: true)
        try VaultBootstrap.reconcileInstall(keyring: ring, sentinel: sentinel)      // later launches: no-op
        XCTAssertEqual(keys.count(scope(.app)), 1)
    }

    func testSweepRemovesOrphanedTempFilesOnly() throws {
        try app.write(payload, .snapshot, to: url(.snapshot), excludeFromBackup: true)
        try Data("junk".utf8).write(to: dir.appendingPathComponent(".snapshot.sealed.tmp123"))
        ProtectedFile.sweep(directory: dir, keeping: ["snapshot.sealed"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["snapshot.sealed"])
    }

    func testDispositionTable() {
        for f in StoreFile.allCases {
            XCTAssertEqual(VaultError.protectedDataUnavailable.disposition(for: f), .retryAfterUnlock)
            XCTAssertEqual(VaultError.storage(code: 1).disposition(for: f), .keepAndReport)
            for e in [VaultError.keyMissing, .malformed, .unsupportedFormat(9), .fileMismatch, .authenticationFailed] {
                XCTAssertEqual(e.disposition(for: f), f == .userState ? .resetUserStateAndTell : .discardAndRebuild)
            }
        }
    }
}

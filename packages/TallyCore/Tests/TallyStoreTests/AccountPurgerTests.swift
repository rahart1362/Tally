import Foundation
import Testing
import TallyTestSupport
@testable import TallyStore
@testable import TallyDomain

@Suite("AccountPurger: file side of sign-out/erase")
struct AccountPurgerTests {
    @Test func purgeRemovesOnlyTheNamedAccountDirectory() async throws {
        let root = try tempStoreDirectory()
        let keys = InMemoryVaultKeyStore()
        let ring = VaultKeyring(store: keys)
        let accountA = AccountKey("account-a")
        let accountB = AccountKey("account-b")

        let storeA = SnapshotStore(root: root, accountKey: accountA,
                                    sealer: VaultSealer(account: accountA.rawValue, keyring: ring, mayCreateKeys: true))
        let storeB = SnapshotStore(root: root, accountKey: accountB,
                                    sealer: VaultSealer(account: accountB.rawValue, keyring: ring, mayCreateKeys: true))
        try await storeA.commit(CanvasSnapshotFixture.make(generation: 1, accountKey: accountA), includeGrades: false)
        try await storeB.commit(CanvasSnapshotFixture.make(generation: 1, accountKey: accountB), includeGrades: false)

        try AccountPurger.purge(accountKey: accountA, root: root, keyring: ring)

        let layoutA = StoreLayout(root: root, accountKey: accountA)
        let layoutB = StoreLayout(root: root, accountKey: accountB)
        #expect(!FileManager.default.fileExists(atPath: layoutA.accountDirectory.path))
        #expect(FileManager.default.fileExists(atPath: layoutB.accountDirectory.path))
        #expect(await storeB.loadSnapshot() != .absent, "account B's data and key must be untouched")

        // Account A's key is shredded, so even a leftover copy of its ciphertext is unreadable.
        #expect(keys.count(KeyScope(account: accountA.rawValue, audience: .app)) == 0)
        #expect(keys.count(KeyScope(account: accountB.rawValue, audience: .app)) == 1)
    }

    /// O5 (PERF-L): the refresh record is one of the account's files, so sign-out's purge removes it
    /// with the rest, and a copy of it could not be opened afterwards.
    @Test func purgeRemovesTheRefreshRecord() throws {
        let root = try tempStoreDirectory()
        let keys = InMemoryVaultKeyStore()
        let ring = VaultKeyring(store: keys)
        let account = AccountKey("account-with-record")
        let sealer = VaultSealer(account: account.rawValue, keyring: ring, mayCreateKeys: true)
        var record = RefreshRecord()
        record.began(.launch, at: Date(timeIntervalSince1970: 1_790_600_400))
        record.failed(.offline)
        let store = RefreshStateStore(root: root, accountKey: account, sealer: sealer)
        try store.save(record)
        let url = StoreLayout(root: root, accountKey: account).url(for: .refreshState)
        let copy = try #require(try ProtectedFile.read(url))

        try AccountPurger.purge(accountKey: account, root: root, keyring: ring)

        #expect(!FileManager.default.fileExists(atPath: url.path), "the refresh record outlived the purge")
        #expect(store.load() == .absent)
        #expect(throws: VaultError.keyMissing) { try sealer.open(copy, file: .refreshState) }
    }

    /// SEC1-08: a failed crypto-shred must not leave the ciphertext behind. `purge` still rethrows
    /// the shred's error (so the caller — `SignOutUseCase` — can log it), but the directory is gone
    /// either way, and the pending-purge marker is cleared once a read-back confirms that.
    @Test func purgeDeletesTheDirectoryEvenWhenTheShredFails() async throws {
        let root = try tempStoreDirectory()
        let keys = InMemoryVaultKeyStore()
        let ring = VaultKeyring(store: keys)
        let account = AccountKey("account-shred-fails")
        let store = SnapshotStore(root: root, accountKey: account,
                                  sealer: VaultSealer(account: account.rawValue, keyring: ring, mayCreateKeys: true))
        try await store.commit(CanvasSnapshotFixture.make(generation: 1, accountKey: account), includeGrades: false)

        keys.failure = .protectedDataUnavailable
        let layout = StoreLayout(root: root, accountKey: account)
        #expect(throws: VaultError.protectedDataUnavailable) {
            try AccountPurger.purge(accountKey: account, root: root, keyring: ring)
        }

        #expect(!FileManager.default.fileExists(atPath: layout.accountDirectory.path),
                "the ciphertext must go even though the key shred failed")
        #expect(!FileManager.default.fileExists(atPath: layout.purgePendingMarker.path),
                "the directory is confirmed gone, so the marker should already be cleared")
    }

    /// SEC1-08: `retryPending` is the next foreground launch's half of the fix — it finds a purge
    /// that left its marker behind (a previous run died, or its directory delete failed at the
    /// time) and finishes it, silently.
    @Test func retryPendingClearsAStaleMarkerAndRemovesTheDirectory() async throws {
        let root = try tempStoreDirectory()
        let keys = InMemoryVaultKeyStore()
        let ring = VaultKeyring(store: keys)
        let account = AccountKey("account-left-pending")
        let scope = KeyScope(account: account.rawValue, audience: .app)
        let store = SnapshotStore(root: root, accountKey: account,
                                  sealer: VaultSealer(account: account.rawValue, keyring: ring, mayCreateKeys: true))
        try await store.commit(CanvasSnapshotFixture.make(generation: 1, accountKey: account), includeGrades: false)
        #expect(keys.count(scope) == 1)

        // Simulate a purge interrupted after it marked pending but before it ran (e.g. the
        // process died): write the marker by hand, with the account directory still present.
        let layout = StoreLayout(root: root, accountKey: account)
        try FileManager.default.createDirectory(at: layout.accountsDirectory, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: layout.purgePendingMarker.path, contents: nil)
        #expect(FileManager.default.fileExists(atPath: layout.accountDirectory.path))

        AccountPurger.retryPending(root: root, keyring: ring)

        #expect(!FileManager.default.fileExists(atPath: layout.accountDirectory.path), "the retry must finish the delete")
        #expect(!FileManager.default.fileExists(atPath: layout.purgePendingMarker.path), "the marker must clear once confirmed gone")
        #expect(keys.count(scope) == 0, "the retry must still shred the key")
    }

    /// A launch with nothing left pending does nothing (and never throws, scanning an `accounts`
    /// directory that may not even exist yet).
    @Test func retryPendingWithNoMarkersDoesNothing() throws {
        let root = try tempStoreDirectory()
        AccountPurger.retryPending(root: root, keyring: VaultKeyring(store: InMemoryVaultKeyStore()))
    }

    /// SEC1-09: when the glance lives in a different (App Group) root than everything else, the
    /// purge must remove both directories — "Sign Out & Erase" must leave nothing in either place.
    @Test func purgeRemovesBothDirectoriesWhenTheGlanceIsSplitOut() async throws {
        let privateRoot = try tempStoreDirectory()
        let sharedRoot = try tempStoreDirectory()
        let keys = InMemoryVaultKeyStore()
        let ring = VaultKeyring(store: keys)
        let account = AccountKey("account-split")
        let sealer = VaultSealer(account: account.rawValue, keyring: ring, mayCreateKeys: true)
        let store = SnapshotStore(root: privateRoot, accountKey: account, sealer: sealer, sharedRoot: sharedRoot)
        try await store.commit(CanvasSnapshotFixture.make(generation: 1, accountKey: account), includeGrades: false)
        let privateLayout = StoreLayout(root: privateRoot, accountKey: account)
        let sharedLayout = StoreLayout(root: sharedRoot, accountKey: account)
        #expect(FileManager.default.fileExists(atPath: privateLayout.url(for: .snapshot).path))
        #expect(FileManager.default.fileExists(atPath: sharedLayout.url(for: .glance).path))

        try AccountPurger.purge(accountKey: account, root: privateRoot, sharedRoot: sharedRoot, keyring: ring)

        #expect(!FileManager.default.fileExists(atPath: privateLayout.accountDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: sharedLayout.accountDirectory.path),
                "the glance's own directory in the App Group root must go with the rest")
        #expect(keys.count(KeyScope(account: account.rawValue, audience: .app)) == 0)
        #expect(!FileManager.default.fileExists(atPath: privateLayout.purgePendingMarker.path))
    }
}

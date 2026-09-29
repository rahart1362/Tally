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
}

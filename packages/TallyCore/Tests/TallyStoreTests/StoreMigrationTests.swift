import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain
@testable import TallyStore

/// SEC1-09: an existing install's files move from the old, combined root (everything, including
/// `accounts.json` and the glance, together — the App Group container when it was available) to
/// the new split layout (`accounts.json` and every account file except the glance in the app's own
/// storage; only the glance stays in the App Group container).
@Suite("StoreMigration: SEC1-09's existing-install move")
struct StoreMigrationTests {
    private let account = AccountRecord.derived(host: "canvas.northfield.example", canvasUserID: "4820117",
                                                clientID: "10000000000042", displayLabel: "Northfield State University")

    /// Builds a pre-SEC1-09 install at `oldRoot`: `accounts.json`, the install sentinel, and one
    /// account's five store files, all together — exactly how `StoreLocation.root(appGroupID:)`
    /// left them before the split.
    private func seedOldLayout(oldRoot: URL, keyring: VaultKeyring) async throws {
        try AccountDirectoryStore(root: oldRoot).activate(account)
        try ProtectedFile.atomicWrite(Data(), to: oldRoot.appendingPathComponent(".installed"), excludeFromBackup: true)
        let sealer = VaultSealer(account: account.accountKey.rawValue, keyring: keyring, mayCreateKeys: true)
        let store = SnapshotStore(root: oldRoot, accountKey: account.accountKey, sealer: sealer)
        try await store.commit(CanvasSnapshotFixture.make(generation: 1, accountKey: account.accountKey), includeGrades: false)
        try await UserStateStore(root: oldRoot, accountKey: account.accountKey, sealer: sealer).save(UserState())
        var record = RefreshRecord()
        record.began(.launch, at: Date(timeIntervalSince1970: 1_790_600_400))
        record.succeeded(dataFetchedAt: Date(timeIntervalSince1970: 1_790_600_400))
        try RefreshStateStore(root: oldRoot, accountKey: account.accountKey, sealer: sealer).save(record)
    }

    @Test("every file moves except the glance, which stays where the widget already finds it")
    func migratesAccountsJSONAndNonGlanceFilesOnly() async throws {
        let oldRoot = try tempStoreDirectory() // stands in for the App Group container
        let newRoot = try tempStoreDirectory() // stands in for the app's own Application Support
        let keyring = VaultKeyring(store: InMemoryVaultKeyStore())
        try await seedOldLayout(oldRoot: oldRoot, keyring: keyring)
        let oldLayout = StoreLayout(root: oldRoot, accountKey: account.accountKey)
        let glanceBefore = try #require(try ProtectedFile.read(oldLayout.url(for: .glance)))

        StoreMigration.migrateIfNeeded(privateRoot: newRoot, oldCombinedRoot: oldRoot)

        // accounts.json and the sentinel moved to the new (private) root.
        #expect(AccountDirectoryStore(root: newRoot).activeAccount() == account)
        #expect(!FileManager.default.fileExists(atPath: oldRoot.appendingPathComponent("accounts.json").path))
        #expect(FileManager.default.fileExists(atPath: newRoot.appendingPathComponent(".installed").path))

        let newLayout = StoreLayout(root: newRoot, accountKey: account.accountKey)
        // The non-glance files moved...
        #expect(FileManager.default.fileExists(atPath: newLayout.url(for: .snapshot).path))
        #expect(FileManager.default.fileExists(atPath: newLayout.url(for: .userState).path))
        #expect(FileManager.default.fileExists(atPath: newLayout.url(for: .refreshState).path))
        #expect(!FileManager.default.fileExists(atPath: oldLayout.url(for: .snapshot).path))
        #expect(!FileManager.default.fileExists(atPath: oldLayout.url(for: .userState).path))
        #expect(!FileManager.default.fileExists(atPath: oldLayout.url(for: .refreshState).path))
        // ...but the glance never moved: it was already in the one place the widget can reach.
        #expect(!FileManager.default.fileExists(atPath: newLayout.url(for: .glance).path))
        #expect(try ProtectedFile.read(oldLayout.url(for: .glance)) == glanceBefore)

        // The migrated snapshot and user state still open with the same keys (nothing was
        // re-encrypted or re-keyed; only moved).
        let sealer = VaultSealer(account: account.accountKey.rawValue, keyring: keyring, mayCreateKeys: false)
        let migratedStore = SnapshotStore(root: newRoot, accountKey: account.accountKey, sealer: sealer, isOwner: false)
        guard case .loaded = await migratedStore.loadSnapshot() else {
            Issue.record("the migrated snapshot did not open")
            return
        }
    }

    @Test("a purge-pending marker (SEC1-08) moves alongside the account directories, never inside one")
    func migratesAPendingPurgeMarker() async throws {
        let oldRoot = try tempStoreDirectory()
        let newRoot = try tempStoreDirectory()
        let keyring = VaultKeyring(store: InMemoryVaultKeyStore())
        try await seedOldLayout(oldRoot: oldRoot, keyring: keyring)
        let oldLayout = StoreLayout(root: oldRoot, accountKey: account.accountKey)
        try FileManager.default.createDirectory(at: oldLayout.accountsDirectory, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: oldLayout.purgePendingMarker.path, contents: nil)

        StoreMigration.migrateIfNeeded(privateRoot: newRoot, oldCombinedRoot: oldRoot)

        let newLayout = StoreLayout(root: newRoot, accountKey: account.accountKey)
        #expect(FileManager.default.fileExists(atPath: newLayout.purgePendingMarker.path))
        #expect(!FileManager.default.fileExists(atPath: oldLayout.purgePendingMarker.path))
    }

    @Test("SEC2-05: an interruption after the account's files move but before accounts.json does is resumed, not stuck, on the next launch")
    func resumesAfterAPartialInterruption() async throws {
        let oldRoot = try tempStoreDirectory()
        let newRoot = try tempStoreDirectory()
        let keyring = VaultKeyring(store: InMemoryVaultKeyStore())
        try await seedOldLayout(oldRoot: oldRoot, keyring: keyring)
        let oldLayout = StoreLayout(root: oldRoot, accountKey: account.accountKey)
        let newLayout = StoreLayout(root: newRoot, accountKey: account.accountKey)

        // Simulate a process death AFTER the per-account files and the install sentinel moved,
        // but BEFORE `accounts.json` did -- exactly the ordering `migrateIfNeeded` now guarantees
        // (accounts.json moves last), and exactly the gap the OLD, accounts.json-first ordering
        // left stranded forever (fileExists(newAccountsJSON) already read as "fully migrated").
        try FileManager.default.createDirectory(at: newLayout.accountDirectory, withIntermediateDirectories: true)
        for file in [StoreFile.snapshot, .userState, .refreshState] {
            try FileManager.default.moveItem(at: oldLayout.url(for: file), to: newLayout.url(for: file))
        }
        try FileManager.default.moveItem(at: oldLayout.installSentinel, to: newLayout.installSentinel)
        #expect(!FileManager.default.fileExists(atPath: newRoot.appendingPathComponent("accounts.json").path),
                "the fixture must start mid-migration, with accounts.json not yet moved")
        let glanceBefore = try #require(try ProtectedFile.read(oldLayout.url(for: .glance)))

        StoreMigration.migrateIfNeeded(privateRoot: newRoot, oldCombinedRoot: oldRoot) // the next launch

        #expect(AccountDirectoryStore(root: newRoot).activeAccount() == account)
        #expect(!FileManager.default.fileExists(atPath: oldRoot.appendingPathComponent("accounts.json").path))
        #expect(FileManager.default.fileExists(atPath: newLayout.url(for: .snapshot).path))
        #expect(FileManager.default.fileExists(atPath: newLayout.url(for: .userState).path))
        #expect(FileManager.default.fileExists(atPath: newLayout.url(for: .refreshState).path))
        // The glance never moves, either run: it was already in the one place the widget reads.
        #expect(!FileManager.default.fileExists(atPath: newLayout.url(for: .glance).path))
        #expect(try ProtectedFile.read(oldLayout.url(for: .glance)) == glanceBefore)

        let sealer = VaultSealer(account: account.accountKey.rawValue, keyring: keyring, mayCreateKeys: false)
        let migratedUserState = await UserStateStore(root: newRoot, accountKey: account.accountKey, sealer: sealer, isOwner: false).load()
        guard case .loaded = migratedUserState else {
            Issue.record("a resumed migration must not leave UserState (Hide Course Names) unreadable: \(migratedUserState)")
            return
        }
        let migratedStore = SnapshotStore(root: newRoot, accountKey: account.accountKey, sealer: sealer, isOwner: false)
        guard case .loaded = await migratedStore.loadSnapshot() else {
            Issue.record("the resumed migration left the snapshot unreadable")
            return
        }
    }

    @Test("idempotent: running it again after a successful migration changes nothing")
    func secondRunIsANoOp() async throws {
        let oldRoot = try tempStoreDirectory()
        let newRoot = try tempStoreDirectory()
        let keyring = VaultKeyring(store: InMemoryVaultKeyStore())
        try await seedOldLayout(oldRoot: oldRoot, keyring: keyring)
        StoreMigration.migrateIfNeeded(privateRoot: newRoot, oldCombinedRoot: oldRoot)
        let newLayout = StoreLayout(root: newRoot, accountKey: account.accountKey)
        let snapshotAfterFirstRun = try #require(try ProtectedFile.read(newLayout.url(for: .snapshot)))

        StoreMigration.migrateIfNeeded(privateRoot: newRoot, oldCombinedRoot: oldRoot) // again

        #expect(AccountDirectoryStore(root: newRoot).activeAccount() == account)
        #expect(try ProtectedFile.read(newLayout.url(for: .snapshot)) == snapshotAfterFirstRun)
    }

    @Test("a fresh install (nothing at the old root) migrates nothing and never throws")
    func freshInstallIsANoOp() throws {
        let oldRoot = try tempStoreDirectory()
        let newRoot = try tempStoreDirectory()
        StoreMigration.migrateIfNeeded(privateRoot: newRoot, oldCombinedRoot: oldRoot)
        #expect(AccountDirectoryStore(root: newRoot).activeAccount() == nil)
        #expect(!FileManager.default.fileExists(atPath: newRoot.appendingPathComponent("accounts.json").path))
    }

    @Test("the App Group was never configured: the two roots are the same directory, so there is nothing to split")
    func sameRootIsANoOp() async throws {
        let root = try tempStoreDirectory()
        let keyring = VaultKeyring(store: InMemoryVaultKeyStore())
        try await seedOldLayout(oldRoot: root, keyring: keyring)

        StoreMigration.migrateIfNeeded(privateRoot: root, oldCombinedRoot: root)

        // Nothing moved: everything is still exactly where it was (the single pre-split layout).
        #expect(AccountDirectoryStore(root: root).activeAccount() == account)
        let layout = StoreLayout(root: root, accountKey: account.accountKey)
        #expect(FileManager.default.fileExists(atPath: layout.url(for: .glance).path))
        #expect(FileManager.default.fileExists(atPath: layout.url(for: .snapshot).path))
    }
}

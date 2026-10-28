import Foundation
import Testing
import TallyTestSupport
@testable import TallyStore
@testable import TallyDomain

/// Item 3 (LIVE-FIX-2/LIVE-3): `etag-cache.sealed`, one account's conditional-GET cache, sealed
/// with the app key in the account directory (SEC1-09: the private store, never the App Group).
/// Rederivable: anything unreadable is discarded and reads as "no cache" -- `CanvasClient` just
/// sends no `If-None-Match` and gets a full 200.
@Suite("ETagCacheStore: the account's conditional-GET cache, sealed and private-store-only")
struct ETagCacheStoreTests {
    let accountKey = AccountKey("acct-etag-cache")

    private func makeSealer(_ keys: InMemoryVaultKeyStore = InMemoryVaultKeyStore(), mayCreateKeys: Bool = true) -> VaultSealer {
        VaultSealer(account: accountKey.rawValue, keyring: VaultKeyring(store: keys), mayCreateKeys: mayCreateKeys)
    }

    private let sample: [String: ETagCacheEntry] = [
        "https://canvas.northfield.example/api/v1/courses": ETagCacheEntry(etag: "\"v1\"", body: Data(#"[{"id":"1"}]"#.utf8)),
        "https://canvas.northfield.example/api/v1/users/self/profile": ETagCacheEntry(etag: "\"v7\"", body: Data(#"{"id":"1"}"#.utf8)),
    ]

    @Test func absentBeforeAnySave() throws {
        let store = ETagCacheStore(root: try tempStoreDirectory(), accountKey: accountKey, sealer: makeSealer())
        #expect(store.load() == .absent)
        #expect(store.loadEntries() == [:])
    }

    @Test func saveThenLoadRoundTrips() throws {
        let root = try tempStoreDirectory()
        let store = ETagCacheStore(root: root, accountKey: accountKey, sealer: makeSealer())
        try store.save(sample)
        #expect(store.load() == .loaded(sample))
        let url = StoreLayout(root: root, accountKey: accountKey).url(for: .etagCache)
        #expect(url.lastPathComponent == "etag-cache.sealed")
        // SEC1-09: the same account directory every other private-store file lives in -- never
        // a shared/App Group root (this type is never even given one to write to).
        #expect(url.deletingLastPathComponent() == StoreLayout(root: root, accountKey: accountKey).accountDirectory)
    }

    @Test func theFileIsSealedNotPlainJSON() throws {
        let root = try tempStoreDirectory()
        try ETagCacheStore(root: root, accountKey: accountKey, sealer: makeSealer()).save(sample)
        let bytes = try #require(try ProtectedFile.read(StoreLayout(root: root, accountKey: accountKey).url(for: .etagCache)))
        #expect(try SealedBlobHeader.decode(from: bytes).file == .etagCache)
        #expect(String(decoding: bytes, as: UTF8.self).contains("\"v1\"") == false, "the cached ETag never appears in plaintext on disk")
    }

    @Test func anUndecodablePayloadIsDiscarded() throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let url = StoreLayout(root: root, accountKey: accountKey).url(for: .etagCache)
        try ProtectedFile.prepareDirectory(url.deletingLastPathComponent(), excludeFromBackup: true)
        try ProtectedFile.atomicWrite(try sealer.seal(Data("garbage".utf8), file: .etagCache), to: url, excludeFromBackup: true)

        #expect(ETagCacheStore(root: root, accountKey: accountKey, sealer: sealer).load() == .absent)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func anotherVersionIsDiscarded() throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let url = StoreLayout(root: root, accountKey: accountKey).url(for: .etagCache)
        try ProtectedFile.prepareDirectory(url.deletingLastPathComponent(), excludeFromBackup: true)
        let future = Data(#"{"version":2,"entries":{}}"#.utf8)
        try ProtectedFile.atomicWrite(try sealer.seal(future, file: .etagCache), to: url, excludeFromBackup: true)

        #expect(ETagCacheStore(root: root, accountKey: accountKey, sealer: sealer).load() == .absent)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aProcessThatDoesNotOwnTheStoreCannotWriteIt() throws {
        let store = ETagCacheStore(root: try tempStoreDirectory(), accountKey: accountKey,
                                   sealer: makeSealer(mayCreateKeys: false), isOwner: false)
        #expect(throws: VaultError.readOnlyProcess) { try store.save(sample) }
    }

    /// The layout's file list is what the foreground orphan sweep keeps: a file missing from it
    /// would be deleted on the next launch.
    @Test func theOrphanSweepKeepsTheCache() async throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        try ETagCacheStore(root: root, accountKey: accountKey, sealer: sealer).save(sample)
        #expect(StoreLayout.allFileNames.contains("etag-cache.sealed"))

        await SnapshotStore(root: root, accountKey: accountKey, sealer: sealer).sweepOrphanedTempFiles()
        #expect(ETagCacheStore(root: root, accountKey: accountKey, sealer: sealer).load() == .loaded(sample))
    }

    // MARK: - SealedETagStore (the async ETagStore adapter CanvasClient actually talks to)

    @Test func sealedETagStorePersistsAcrossInstances() async throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let first = SealedETagStore(ETagCacheStore(root: root, accountKey: accountKey, sealer: sealer))
        #expect(await first.entry(for: "https://canvas.northfield.example/api/v1/courses") == nil)
        let entry = ETagCacheEntry(etag: "\"abc\"", body: Data(#"[{"id":"1"}]"#.utf8))
        await first.setEntry(entry, for: "https://canvas.northfield.example/api/v1/courses")
        #expect(await first.entry(for: "https://canvas.northfield.example/api/v1/courses") == entry)

        // A fresh instance (a new sign-in/launch's CanvasClient): reads what the first wrote.
        let second = SealedETagStore(ETagCacheStore(root: root, accountKey: accountKey, sealer: sealer))
        #expect(await second.entry(for: "https://canvas.northfield.example/api/v1/courses") == entry)
    }

    @Test func sealedETagStoreKeepsOtherKeysWhenOneIsUpdated() async throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let store = SealedETagStore(ETagCacheStore(root: root, accountKey: accountKey, sealer: sealer))
        let coursesKey = "https://canvas.northfield.example/api/v1/courses"
        let profileKey = "https://canvas.northfield.example/api/v1/users/self/profile"
        await store.setEntry(ETagCacheEntry(etag: "\"c1\"", body: Data()), for: coursesKey)
        await store.setEntry(ETagCacheEntry(etag: "\"p1\"", body: Data()), for: profileKey)
        await store.setEntry(ETagCacheEntry(etag: "\"c2\"", body: Data()), for: coursesKey)

        #expect(await store.entry(for: coursesKey)?.etag == "\"c2\"")
        #expect(await store.entry(for: profileKey)?.etag == "\"p1\"")
    }
}

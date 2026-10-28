import Foundation
import Testing
import TallyCanvasAPI
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
        let future = Data(#"{"version":3,"entries":{}}"#.utf8) // currentVersion is 2 (item 3 round 2)
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
        // Item 3 round 2: `setEntry` is memory-only now -- `flush()` is the one write.
        await first.flush()

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

    // MARK: - Item 3 round 2 (PMO review of PR #101): bounded growth

    @Test("Age alone bounds the cache: 30 daily refreshes, shifting date-window URLs, stable URLs survive")
    func thirtyDailyRefreshesStayBounded() {
        var entries: [String: ETagCacheEntry] = [:]
        let anchor = Date(timeIntervalSince1970: 1_790_600_400)
        let stableKeys = ["courses", "profile", "assignment_groups/1", "assignment_groups/2", "assignment_groups/3"]
        for day in 0..<30 {
            let now = anchor.addingTimeInterval(TimeInterval(day) * 86_400)
            // The 5 endpoints whose own query never changes: touched (refreshed) every day,
            // exactly like a real refresh's 304 hit updating `lastUsedAt`.
            for key in stableKeys {
                entries[key] = ETagCacheEntry(etag: "\"\(key)-v\(day)\"", body: Data(repeating: 1, count: 2_000), lastUsedAt: now)
            }
            // The planner/calendar/announcement shape: a brand new URL every day
            // (`CanvasDateWindow.dateString`), never touched again after today.
            entries["planner/day-\(day)"] = ETagCacheEntry(etag: "\"planner-\(day)\"", body: Data(repeating: 2, count: 2_000), lastUsedAt: now)
            entries = ETagCachePruning.pruned(entries, now: now, maxAge: TallyConfig.etagCacheEntryMaxAge,
                                              maxBytes: TallyConfig.etagCacheMaxBodyBytes)
        }
        // `maxAge` is 2 days, and the prune keeps anything `<= maxAge` old, so at most 3 days'
        // worth of daily-changing entries survive (today, yesterday, the day before), never 30.
        let plannerSurvivors = entries.keys.filter { $0.hasPrefix("planner/") }
        #expect(plannerSurvivors.count <= 3, "got \(plannerSurvivors.count): \(plannerSurvivors.sorted())")
        for key in stableKeys {
            #expect(entries[key] != nil, "\(key) is touched every day and must never age out")
        }
        #expect(entries.count <= stableKeys.count + 3)
    }

    @Test("Over the byte cap, the least-recently-used entries are evicted first")
    func evictsLeastRecentlyUsedFirstUnderTheByteCap() {
        let anchor = Date(timeIntervalSince1970: 1_790_600_400)
        // 5 entries, 100 bytes apiece, each used a minute after the last -- "oldest" is well
        // (0) and "newest" is well (4).
        var entries: [String: ETagCacheEntry] = [:]
        for i in 0..<5 {
            entries["key\(i)"] = ETagCacheEntry(etag: "\"e\(i)\"", body: Data(repeating: UInt8(i), count: 100),
                                                lastUsedAt: anchor.addingTimeInterval(TimeInterval(i) * 60))
        }
        // A cap that only fits the 2 most recent 100-byte entries.
        let pruned = ETagCachePruning.pruned(entries, now: anchor.addingTimeInterval(300), maxAge: .seconds(3600), maxBytes: 250)
        #expect(Set(pruned.keys) == ["key3", "key4"], "got \(pruned.keys.sorted())")
    }

    // MARK: - Item 3 round 2: one write per refresh, and EB-26's erase

    private final class CountingSealer: SnapshotSealer, @unchecked Sendable {
        private let wrapped: any SnapshotSealer
        private let lock = NSLock()
        private var counts: [StoreFile: Int] = [:]
        init(wrapping sealer: any SnapshotSealer) { wrapped = sealer }
        func seal(_ plaintext: Data, file: StoreFile) throws -> Data {
            lock.withLock { counts[file, default: 0] += 1 }
            return try wrapped.seal(plaintext, file: file)
        }
        func open(_ sealed: Data, file: StoreFile) throws -> Data { try wrapped.open(sealed, file: file) }
        func sealCount(for file: StoreFile) -> Int { lock.withLock { counts[file, default: 0] } }
    }

    private struct NeverCalledRefresher: TokenRefreshing {
        func refresh(_ credential: CanvasCredential) async throws -> CanvasCredential { throw AuthError.reauthRequired }
    }

    private func gatewayWithRealETagStore(root: URL, sealer: any SnapshotSealer, transport: ReplayTransport)
        -> LiveCanvasGateway {
        let host = "canvas.northfield.example"
        let credential = CanvasCredential(host: host, userID: "4820117", accessToken: "t", refreshToken: "r",
                                          accessTokenExpiresAt: .distantFuture)
        let tokens = TokenCoordinator(initial: credential, store: InMemoryCredentialStore(credential),
                                      refresher: NeverCalledRefresher(), clock: TestClock())
        let etagStore = SealedETagStore(ETagCacheStore(root: root, accountKey: accountKey, sealer: sealer))
        let client = CanvasClient(host: host, transport: transport, tokens: tokens, etags: etagStore)
        return LiveCanvasGateway(host: host, accountKey: accountKey, client: client)
    }

    /// `fixtures/canvas`'s own replayed responses never carry an `ETag` (the round-1 doc comment
    /// on `ETagCacheTests.swift` already notes this), so without this injection nothing would
    /// ever be cached at all and "exactly one save" would be vacuously true for the wrong
    /// reason. Profile is required and fetched first, so this alone guarantees `setEntry` runs
    /// at least once before either test's own outcome (success or a later failure).
    private func injectCacheableProfile(_ transport: ReplayTransport) async throws {
        let body = try Fixtures.data("personas/flagship/profile.json")
        await transport.inject(response: HTTPResponse(status: 200, headers: HTTPHeaders(["ETag": "\"profile-v1\""]), body: body),
                               times: 1, matching: { $0.url.path == "/api/v1/users/self/profile" })
    }

    @Test("A successful refresh writes the ETag cache exactly once, no matter how many endpoints carried an ETag")
    func exactlyOneSaveOnASuccessfulRefresh() async throws {
        let root = try tempStoreDirectory()
        let sealer = CountingSealer(wrapping: makeSealer())
        let transport = try ReplayTransport.persona("flagship")
        try await injectCacheableProfile(transport)
        let gateway = gatewayWithRealETagStore(root: root, sealer: sealer, transport: transport)

        _ = try await gateway.fetchSnapshot(previous: nil, now: Date())
        #expect(sealer.sealCount(for: .etagCache) == 1, "one flush for the whole refresh, not one per ETag-bearing response")
    }

    @Test("A failed refresh still flushes exactly once what it already cached (never zero, never once per endpoint)")
    func exactlyOneSaveOnAFailedRefresh() async throws {
        let root = try tempStoreDirectory()
        let sealer = CountingSealer(wrapping: makeSealer())
        let transport = try ReplayTransport.persona("flagship")
        try await injectCacheableProfile(transport) // profile (required, fetched first) succeeds and is cached
        await transport.inject(response: try ReplayTransport.errorResponse("500-internal-server-error"), times: 3,
                               matching: { $0.url.path == "/api/v1/courses" }) // then courses (required, next) fails
        let gateway = gatewayWithRealETagStore(root: root, sealer: sealer, transport: transport)

        await #expect(throws: RefreshFailure.server) { _ = try await gateway.fetchSnapshot(previous: nil, now: Date()) }
        #expect(sealer.sealCount(for: .etagCache) == 1, "the profile entry cached before the failure is still flushed, exactly once")
    }

    @Test("EB-26 'Erase Saved Data': clearLocalCaches empties the in-memory cache so a later flush cannot resurrect it")
    func clearLocalCachesPreventsResurrectionAfterErase() async throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let transport = try ReplayTransport.persona("flagship")
        try await injectCacheableProfile(transport)
        let gateway = gatewayWithRealETagStore(root: root, sealer: sealer, transport: transport)

        _ = try await gateway.fetchSnapshot(previous: nil, now: Date())
        let url = StoreLayout(root: root, accountKey: accountKey).url(for: .etagCache)
        #expect(FileManager.default.fileExists(atPath: url.path), "the first refresh did persist a cache")

        // The purge (AccountPurger.eraseCanvasData, exercised elsewhere) deletes the file; this
        // gateway's own in-memory copy must not be able to write it back afterwards.
        ProtectedFile.remove(url)
        await gateway.clearLocalCaches()
        try await injectCacheableProfile(transport) // the first injection was consumed by the first fetch
        _ = try await gateway.fetchSnapshot(previous: nil, now: Date())

        // Without the clear, this second fetch's profile request would have carried the
        // pre-erase entry's `If-None-Match` (the same URL both times) -- proving the in-memory
        // cache, not just the file, was actually emptied.
        let profileRequests = await transport.requests().filter { $0.url.path == "/api/v1/users/self/profile" }
        #expect(profileRequests.count == 2, "one profile request per fetchSnapshot call")
        #expect(profileRequests.last?.headers["If-None-Match"] == nil,
               "the post-clear refresh's profile request must be unconditional: nothing survived the clear to attach")
        #expect(FileManager.default.fileExists(atPath: url.path), "the second, post-clear refresh caches again -- this is a fresh cache, not a resurrection")
    }
}

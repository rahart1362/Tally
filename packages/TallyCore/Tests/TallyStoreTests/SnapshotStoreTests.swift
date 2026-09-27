import Foundation
import Testing
import TallyTestSupport
@testable import TallyStore
@testable import TallyDomain

/// WP-C01: layout, envelope, generations, and the atomic commit protocol (architecture.md §3.2).
@Suite("SnapshotStore: atomic commit, generations, and self-heal")
struct SnapshotStoreTests {
    let accountKey = AccountKey("acct-c01")

    private func makeSealer(_ keys: InMemoryVaultKeyStore = InMemoryVaultKeyStore()) -> VaultSealer {
        VaultSealer(account: accountKey.rawValue, keyring: VaultKeyring(store: keys), mayCreateKeys: true)
    }

    @Test func commitThenLoadRoundTripsSnapshotAndGlance() async throws {
        let root = try tempStoreDirectory()
        let store = SnapshotStore(root: root, accountKey: accountKey, sealer: makeSealer())
        let snapshot = CanvasSnapshotFixture.make(generation: 1)

        try await store.commit(snapshot, includeGrades: false)

        guard case .loaded(let loaded) = await store.loadSnapshot() else { Issue.record("expected a loaded snapshot"); return }
        #expect(loaded == snapshot)
        guard case .loaded(let glance) = await store.loadGlance() else { Issue.record("expected a loaded glance"); return }
        #expect(glance.generation == 1)
        #expect(glance.overallGradeBand == nil, "includeGrades was false")
    }

    @Test func onlyTheSnapshotAndGlanceFilesExistAfterCommit() async throws {
        let root = try tempStoreDirectory()
        let store = SnapshotStore(root: root, accountKey: accountKey, sealer: makeSealer())
        try await store.commit(CanvasSnapshotFixture.make(generation: 1), includeGrades: false)
        let dir = StoreLayout(root: root, accountKey: accountKey).accountDirectory
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["glance.v1.sealed", "snapshot.v1.sealed"])
    }

    @Test func staleOrEqualGenerationIsRejectedAndOriginalSurvives() async throws {
        let root = try tempStoreDirectory()
        let store = SnapshotStore(root: root, accountKey: accountKey, sealer: makeSealer())
        let first = CanvasSnapshotFixture.make(generation: 5)
        try await store.commit(first, includeGrades: false)

        await #expect(throws: SnapshotStoreError.staleGeneration(attempted: 5, current: 5)) {
            try await store.commit(CanvasSnapshotFixture.make(generation: 5), includeGrades: false)
        }
        await #expect(throws: SnapshotStoreError.staleGeneration(attempted: 3, current: 5)) {
            try await store.commit(CanvasSnapshotFixture.make(generation: 3), includeGrades: false)
        }

        guard case .loaded(let loaded) = await store.loadSnapshot() else { Issue.record("expected the original snapshot"); return }
        #expect(loaded == first)
    }

    @Test func higherGenerationReplacesTheOldOneAtomically() async throws {
        let root = try tempStoreDirectory()
        let store = SnapshotStore(root: root, accountKey: accountKey, sealer: makeSealer())
        try await store.commit(CanvasSnapshotFixture.make(generation: 1), includeGrades: false)
        try await store.commit(CanvasSnapshotFixture.make(generation: 2), includeGrades: false)
        guard case .loaded(let loaded) = await store.loadSnapshot() else { Issue.record("expected a loaded snapshot"); return }
        #expect(loaded.generation == 2)
    }

    /// An older `CanvasSnapshot.schemaVersion` is discarded, never migrated (architecture.md §3.2).
    @Test func olderSchemaVersionIsDiscardedNotMigrated() async throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let layout = StoreLayout(root: root, accountKey: accountKey)
        try ProtectedFile.prepareDirectory(layout.accountDirectory, excludeFromBackup: true)

        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(CanvasSnapshotFixture.make())) as! [String: Any]
        json["schemaVersion"] = 0 // simulate a payload written by an older, incompatible schema
        let legacyPayload = try JSONSerialization.data(withJSONObject: json)
        try ProtectedFile.atomicWrite(try sealer.seal(legacyPayload, file: .snapshot), to: layout.url(for: .snapshot), excludeFromBackup: true)

        let store = SnapshotStore(root: root, accountKey: accountKey, sealer: sealer)
        #expect(await store.loadSnapshot() == .absent)
        #expect(!FileManager.default.fileExists(atPath: layout.url(for: .snapshot).path), "the old-schema file must be discarded, not kept")
    }

    /// Crash-injection test (WP-C01): the app dies between the snapshot write and the glance
    /// write. The only possible on-disk state is a glance behind the snapshot's generation; the
    /// next load must still return a consistent snapshot and self-heal the glance from it.
    @Test func crashBetweenSnapshotAndGlanceWritesStillLoadsConsistently() async throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let layout = StoreLayout(root: root, accountKey: accountKey)
        let store = SnapshotStore(root: root, accountKey: accountKey, sealer: sealer)

        try await store.commit(CanvasSnapshotFixture.make(generation: 1), includeGrades: false)
        guard case .loaded(let staleGlance) = await store.loadGlance() else { Issue.record("expected glance gen 1"); return }
        #expect(staleGlance.generation == 1)

        // Simulate the crash: write generation 2's snapshot directly, bypassing `commit`, so the
        // glance is left behind at generation 1 (as if the process died before the second write).
        let crashed = CanvasSnapshotFixture.make(generation: 2)
        try ProtectedFile.atomicWrite(try sealer.seal(JSONEncoder().encode(crashed), file: .snapshot),
                                      to: layout.url(for: .snapshot), excludeFromBackup: true)

        guard case .loaded(let recovered) = await store.loadSnapshot() else { Issue.record("expected a loaded snapshot after the crash"); return }
        #expect(recovered.generation == 2, "the snapshot itself survives a crash mid-commit")

        guard case .loaded(let healedGlance) = await store.loadGlance() else { Issue.record("expected the glance to self-heal"); return }
        #expect(healedGlance.generation == 2, "the glance must be rebuilt to match, not left stale")
    }

    @Test func aNonOwnerNeverRepairsTheGlance() async throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let layout = StoreLayout(root: root, accountKey: accountKey)
        let owner = SnapshotStore(root: root, accountKey: accountKey, sealer: sealer, isOwner: true)
        try await owner.commit(CanvasSnapshotFixture.make(generation: 1), includeGrades: false)

        // Simulate the same crash as above, but this time read it with a non-owner store (the
        // shape a widget-like reader would use, sharing the same sealer for this test's purposes).
        let crashed = CanvasSnapshotFixture.make(generation: 2)
        try ProtectedFile.atomicWrite(try sealer.seal(JSONEncoder().encode(crashed), file: .snapshot),
                                      to: layout.url(for: .snapshot), excludeFromBackup: true)

        let reader = SnapshotStore(root: root, accountKey: accountKey, sealer: sealer, isOwner: false)
        guard case .loaded(let loaded) = await reader.loadSnapshot() else { Issue.record("expected a loaded snapshot"); return }
        #expect(loaded.generation == 2)

        // The glance on disk must be untouched: still generation 1, never repaired by a non-owner.
        guard case .loaded(let untouchedGlance) = await owner.loadGlance() else { Issue.record("expected the original glance"); return }
        #expect(untouchedGlance.generation == 1)
    }

    @Test func sweepRemovesOrphanedTempFilesButKeepsRealOnes() async throws {
        let root = try tempStoreDirectory()
        let store = SnapshotStore(root: root, accountKey: accountKey, sealer: makeSealer())
        try await store.commit(CanvasSnapshotFixture.make(generation: 1), includeGrades: false)
        let dir = StoreLayout(root: root, accountKey: accountKey).accountDirectory
        try Data("junk".utf8).write(to: dir.appendingPathComponent(".snapshot.v1.sealed.tmp999"))

        await store.sweepOrphanedTempFiles()

        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["glance.v1.sealed", "snapshot.v1.sealed"])
    }
}

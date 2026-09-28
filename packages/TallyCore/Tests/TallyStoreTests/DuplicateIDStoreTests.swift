import Foundation
import Testing
import TallyTestSupport
@testable import TallyStore
@testable import TallyDomain

/// CS-07 (crash-safety-2.md, CS7-1): `GlanceProjectionBuilder` and `SnapshotStore` survive a
/// snapshot that repeats an identifier.
///
/// Before CS-07 a repeated course ID trapped in `GlanceProjectionBuilder.build`
/// (`Dictionary(uniqueKeysWithValues:)`). `SnapshotStore.commit` seals and writes the snapshot
/// *before* it builds the glance, so the trap left the repeated snapshot on disk with an older
/// glance, and the next `loadSnapshot()` rebuilt the glance and trapped again: a crash at every
/// launch, not a one-off.
@Suite("Repeated identifiers: glance projection and snapshot store never trap (CS-07)", .timeLimit(.minutes(1)))
struct DuplicateIDStoreTests {
    private let accountKey = AccountKey("duplicate-id-fixture")

    private func makeStore(root: URL) -> (SnapshotStore, VaultSealer) {
        let sealer = VaultSealer(account: accountKey.rawValue, keyring: VaultKeyring(store: InMemoryVaultKeyStore()),
                                 mayCreateKeys: true)
        return (SnapshotStore(root: root, accountKey: accountKey, sealer: sealer), sealer)
    }

    // MARK: - GlanceProjectionBuilder

    @Test(arguments: DuplicateIDFixture.Kind.allCases)
    func glanceProjectionSurvivesARepeatedID(_ kind: DuplicateIDFixture.Kind) {
        let snapshot = DuplicateIDFixture.snapshot(duplicating: kind)
        for includeGrades in [false, true] {
            let glance = GlanceProjectionBuilder.build(from: snapshot, includeGrades: includeGrades)
            #expect(glance.generation == snapshot.generation)
            #expect(!glance.dueSoon.isEmpty)
        }
    }

    /// First occurrence wins: the Biology planner item keeps the original course's short code,
    /// not the repeated course's "BIO REPEAT".
    @Test func glanceProjectionKeepsTheFirstOfARepeatedCourse() {
        let glance = GlanceProjectionBuilder.build(from: DuplicateIDFixture.snapshot(duplicating: .course), includeGrades: false)
        let biologyItem = glance.dueSoon.first { $0.id == "assignment:8111" }
        #expect(biologyItem?.courseShortCode == "BIO 101")
    }

    // MARK: - SnapshotStore

    @Test func commitAndLoadSurviveEveryRepeatedIDAtOnce() async throws {
        let (store, _) = makeStore(root: try tempStoreDirectory())
        let snapshot = DuplicateIDFixture.snapshot(duplicating: DuplicateIDFixture.Kind.allCases)
        let glance = try await store.commit(snapshot, includeGrades: true)
        #expect(glance.generation == 1)
        guard case .loaded(let loaded) = await store.loadSnapshot() else { Issue.record("expected the committed snapshot"); return }
        #expect(loaded == snapshot)
        guard case .loaded(let reloadedGlance) = await store.loadGlance() else { Issue.record("expected a glance"); return }
        #expect(reloadedGlance == glance)
    }

    /// The on-disk state the old trap left behind: a sealed snapshot with a repeated course and no
    /// glance for its generation. `loadSnapshot()` must load it and rebuild the glance, not trap.
    @Test func loadSelfHealsTheGlanceOfAPersistedSnapshotWithARepeatedCourse() async throws {
        let root = try tempStoreDirectory()
        let (store, sealer) = makeStore(root: root)
        try await store.commit(DuplicateIDFixture.base(generation: 1), includeGrades: false)

        let repeated = DuplicateIDFixture.snapshot(duplicating: .course, generation: 2)
        let access = SealedFileAccess(sealer: sealer, isOwner: true)
        try access.write(try JSONEncoder().encode(repeated), .snapshot,
                         to: StoreLayout(root: root, accountKey: accountKey).url(for: .snapshot), excludeFromBackup: true)

        guard case .loaded(let loaded) = await store.loadSnapshot() else { Issue.record("expected the repeated snapshot"); return }
        #expect(loaded.generation == 2)
        guard case .loaded(let glance) = await store.loadGlance() else { Issue.record("expected a rebuilt glance"); return }
        #expect(glance.generation == 2, "the glance was rebuilt for the loaded generation")
    }

    // MARK: - SnapshotBudget

    @Test(arguments: DuplicateIDFixture.Kind.allCases)
    func snapshotBudgetSurvivesARepeatedID(_ kind: DuplicateIDFixture.Kind) {
        let snapshot = DuplicateIDFixture.snapshot(duplicating: kind)
        let outcome = SnapshotBudget.enforce(snapshot, maxItems: 5)
        #expect(outcome.degraded)
        #expect(outcome.snapshot.courses == snapshot.courses, "courses are never trimmed")
    }
}

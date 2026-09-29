import Foundation
import Testing
import TallyTestSupport
@testable import TallyStore
@testable import TallyDomain

/// `SnapshotStore.rewriteGlance`: "Show Grades in Widgets" takes effect on the glance at once
/// (M3-A O11, PMO R10), and never for any snapshot but the committed one.
@Suite("SnapshotStore.rewriteGlance: grade opt-in changes reach the glance now")
struct GlanceRewriteTests {
    let accountKey = AccountKey("acct-glance-rewrite")

    private func makeStore(root: URL, isOwner: Bool = true) -> SnapshotStore {
        let sealer = VaultSealer(account: accountKey.rawValue, keyring: VaultKeyring(store: InMemoryVaultKeyStore()), mayCreateKeys: true)
        return SnapshotStore(root: root, accountKey: accountKey, sealer: sealer, isOwner: isOwner)
    }

    private static func hasGrades(_ glance: GlanceProjection) -> Bool {
        glance.overallGradeBand != nil || glance.courses.contains { $0.currentGrade != nil }
    }

    @Test func turningGradesOffRemovesThemFromTheGlanceOnDisk() async throws {
        let store = makeStore(root: try tempStoreDirectory())
        let snapshot = CanvasSnapshotFixture.make(generation: 3)
        try await store.commit(snapshot, includeGrades: true)
        guard case .loaded(let before) = await store.loadGlance() else { Issue.record("expected a glance"); return }
        #expect(Self.hasGrades(before), "the fixture has grades, and the commit opted in")

        let rewritten = try await store.rewriteGlance(from: snapshot, includeGrades: false)

        #expect(rewritten.map(Self.hasGrades) == false)
        guard case .loaded(let after) = await store.loadGlance() else { Issue.record("expected a glance"); return }
        #expect(!Self.hasGrades(after))
        #expect(after.generation == 3)
        guard case .loaded(let onDisk) = await store.loadSnapshot() else { Issue.record("expected the snapshot"); return }
        #expect(onDisk == snapshot, "the snapshot is untouched")
    }

    @Test func aSnapshotThatIsNotTheCommittedOneWritesNothing() async throws {
        let store = makeStore(root: try tempStoreDirectory())
        try await store.commit(CanvasSnapshotFixture.make(generation: 4), includeGrades: true)

        let older = try await store.rewriteGlance(from: CanvasSnapshotFixture.make(generation: 3), includeGrades: false)
        let newer = try await store.rewriteGlance(from: CanvasSnapshotFixture.make(generation: 5), includeGrades: false)

        #expect(older == nil)
        #expect(newer == nil)
        guard case .loaded(let glance) = await store.loadGlance() else { Issue.record("expected a glance"); return }
        #expect(Self.hasGrades(glance) && glance.generation == 4, "the committed glance is unchanged")
    }

    @Test func nothingCommittedOrNotTheOwnerWritesNothing() async throws {
        let root = try tempStoreDirectory()
        let empty = makeStore(root: root)
        #expect(try await empty.rewriteGlance(from: CanvasSnapshotFixture.make(generation: 1), includeGrades: false) == nil)
        #expect(await empty.loadGlance() == .absent)

        let snapshot = CanvasSnapshotFixture.make(generation: 1)
        try await empty.commit(snapshot, includeGrades: true)
        let widget = makeStore(root: root, isOwner: false)
        #expect(try await widget.rewriteGlance(from: snapshot, includeGrades: false) == nil, "a non-owner (the widget) never writes")
    }
}

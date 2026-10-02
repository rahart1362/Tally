import Foundation
import Testing
import TallyTestSupport
@testable import TallyStore
@testable import TallyDomain

/// PAY-04 (M3-B1): the glance's additive `entitledUntil`, the expiry the entitlement gate mirrors
/// for the widgets and intents. Written by every glance write the store makes, carried forward by
/// its self-heal, absent from a glance written before it, and read through `coversSubscription(at:)`.
@Suite("Glance entitledUntil (PAY-04): the mirrored expiry")
struct GlanceEntitlementTests {
    let accountKey = AccountKey("acct-glance-entitlement")
    static let until = Date(timeIntervalSince1970: 1_800_000_000)
    static let day: TimeInterval = 24 * 60 * 60

    private func makeStore(root: URL, sealer: VaultSealer? = nil) -> SnapshotStore {
        let sealer = sealer ?? makeSealer()
        return SnapshotStore(root: root, accountKey: accountKey, sealer: sealer)
    }

    private func makeSealer() -> VaultSealer {
        VaultSealer(account: accountKey.rawValue, keyring: VaultKeyring(store: InMemoryVaultKeyStore()), mayCreateKeys: true)
    }

    private func glance(_ store: SnapshotStore) async -> GlanceProjection? {
        guard case .loaded(let glance) = await store.loadGlance() else { return nil }
        return glance
    }

    @Test("A commit writes the expiry it is given; none by default")
    func commitWritesTheExpiry() async throws {
        let store = makeStore(root: try tempStoreDirectory())
        let written = try await store.commit(CanvasSnapshotFixture.make(generation: 1), includeGrades: false,
                                             entitledUntil: Self.until)
        #expect(written.entitledUntil == Self.until)
        #expect(await glance(store)?.entitledUntil == Self.until)
        try await store.commit(CanvasSnapshotFixture.make(generation: 2), includeGrades: false)
        #expect(await glance(store)?.entitledUntil == nil, "the caller decides; nothing is carried into a commit")
    }

    @Test("A rewrite writes the expiry it is given, and keeps every other field")
    func rewriteWritesTheExpiry() async throws {
        let store = makeStore(root: try tempStoreDirectory())
        let snapshot = CanvasSnapshotFixture.make(generation: 3)
        let committed = try await store.commit(snapshot, includeGrades: true)
        let rewritten = try await store.rewriteGlance(from: snapshot, includeGrades: true, entitledUntil: Self.until)
        #expect(rewritten?.entitledUntil == Self.until)
        let onDisk = try #require(await glance(store))
        #expect(onDisk.entitledUntil == Self.until)
        #expect(onDisk.generation == committed.generation && onDisk.courses == committed.courses
                && onDisk.dueSoon == committed.dueSoon && onDisk.gradeSummary == committed.gradeSummary)
    }

    @Test("The self-heal carries the old glance's expiry forward")
    func selfHealCarriesTheExpiryForward() async throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let store = makeStore(root: root, sealer: sealer)
        try await store.commit(CanvasSnapshotFixture.make(generation: 1), includeGrades: false, entitledUntil: Self.until)
        // A crash between the snapshot write and the glance write (as SnapshotStoreTests does it).
        let crashed = CanvasSnapshotFixture.make(generation: 2)
        try ProtectedFile.atomicWrite(try sealer.seal(JSONEncoder().encode(crashed), file: .snapshot),
                                      to: StoreLayout(root: root, accountKey: accountKey).url(for: .snapshot),
                                      excludeFromBackup: true)
        guard case .loaded = await store.loadSnapshot() else { Issue.record("expected the snapshot"); return }
        let healed = try #require(await glance(store))
        #expect(healed.generation == 2, "rebuilt")
        #expect(healed.entitledUntil == Self.until, "the mirrored expiry survives the rebuild")
    }

    @Test("A glance written before the field decodes with none")
    func olderGlanceHasNone() throws {
        let glance = GlanceProjectionBuilder.build(from: CanvasSnapshotFixture.make(generation: 1), includeGrades: false)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(glance)) as? [String: Any] ?? [:]
        json["entitledUntil"] = nil
        let decoded = try JSONDecoder().decode(GlanceProjection.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.entitledUntil == nil)
        #expect(decoded == glance)
    }

    @Test("coversSubscription: open until the grace ends, the glance's asOf counts as reached, open when not enforced")
    func coversSubscription() {
        let asOf = Self.until.addingTimeInterval(-Self.day)
        let snapshot = CanvasSnapshotFixture.make(generation: 1, fetchedAt: asOf)
        let entitled = GlanceProjectionBuilder.build(from: snapshot, includeGrades: false, entitledUntil: Self.until)
        let grace = SubscriptionConfig.offlineGracePeriod.timeInterval
        #expect(entitled.coversSubscription(at: Self.until.addingTimeInterval(grace - 1), isEnforced: true))
        #expect(!entitled.coversSubscription(at: Self.until.addingTimeInterval(grace), isEnforced: true))
        let none = GlanceProjectionBuilder.build(from: snapshot, includeGrades: false)
        #expect(!none.coversSubscription(at: asOf, isEnforced: true), "no expiry: locked (fails closed)")
        #expect(none.coversSubscription(at: asOf, isEnforced: false), "not enforced: open")
        // A clock set back to before the glance was written cannot unlock an expired glance.
        let late = CanvasSnapshotFixture.make(generation: 1, fetchedAt: Self.until.addingTimeInterval(grace + Self.day))
        let expired = GlanceProjectionBuilder.build(from: late, includeGrades: false, entitledUntil: Self.until)
        #expect(!expired.coversSubscription(at: Self.until, isEnforced: true))
    }
}

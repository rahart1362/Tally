import Foundation
import Testing
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallySync

/// PAY-07 and PAY-04 (M3-B1) at the coordinator, the one place every refresh trigger reaches the
/// network: the subscription gates refresh (the first sync stays free), and every glance the
/// coordinator writes mirrors the gate's expiry; `entitlementDidChange()` rewrites it at once.
@Suite("RefreshCoordinator and the entitlement gate (PAY-07, PAY-04)", .timeLimit(.minutes(TestTimeBudget.minutes(1))))
struct RefreshCoordinatorEntitlementTests {
    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let until = now.addingTimeInterval(30 * 24 * 60 * 60)

    private func make(gate: any EntitlementGating, initialSnapshot: CanvasSnapshot? = nil, includeGrades: Bool = false)
        throws -> (RefreshCoordinator, SnapshotStore, ScriptedGateway) {
        let accountKey = AccountKey("entitlement-gate")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tally-entitlement-\(UUID().uuidString)")
        try ProtectedFile.prepareDirectory(root, excludeFromBackup: true)
        let sealer = VaultSealer(account: accountKey.rawValue, keyring: VaultKeyring(store: InMemoryVaultKeyStore()),
                                 mayCreateKeys: true)
        let store = SnapshotStore(root: root, accountKey: accountKey, sealer: sealer)
        let gateway = ScriptedGateway()
        let coordinator = RefreshCoordinator(gateway: gateway, store: store, clock: TestClock(Self.now),
                                             initialSnapshot: initialSnapshot, includeGrades: includeGrades,
                                             liveRefreshBudget: .seconds(30), foregroundHardCeiling: .seconds(60),
                                             backgroundBudget: .seconds(60), entitlement: gate)
        return (coordinator, store, gateway)
    }

    private func glance(_ store: SnapshotStore) async -> GlanceProjection? {
        guard case .loaded(let glance) = await store.loadGlance() else { return nil }
        return glance
    }

    private func enforced(_ state: EntitlementState) -> EntitlementGate {
        EntitlementGate(isEnforced: true, clock: TestClock(Self.now), state: state)
    }

    @Test("Lapsed with a committed snapshot: no trigger fetches, and nothing changes", arguments: RefreshTrigger.allCases)
    func lapsedRefusesEveryTrigger(_ trigger: RefreshTrigger) async throws {
        let cached = CanvasSnapshotFixture.make(generation: 1, fetchedAt: Self.now.addingTimeInterval(-3_600))
        let (coordinator, store, gateway) = try make(gate: enforced(.lapsed(since: Self.now)), initialSnapshot: cached)
        let before = await coordinator.currentState
        let after = await coordinator.run(trigger: trigger)
        #expect(await gateway.calls == 0, "\(trigger) reached the network after a lapse")
        #expect(after == before)
        #expect(await coordinator.committedSnapshot == cached, "the last snapshot stays readable")
        #expect(await store.loadGlance() == .absent, "nothing was written")
    }

    @Test("Preview (never subscribed) with a committed snapshot: refused too")
    func previewRefuses() async throws {
        let cached = CanvasSnapshotFixture.make(generation: 1, fetchedAt: Self.now)
        let (coordinator, _, gateway) = try make(gate: enforced(.preview), initialSnapshot: cached)
        _ = await coordinator.run(trigger: .manual)
        #expect(await gateway.calls == 0)
    }

    @Test("The first sync (nothing committed) is free whatever the state", arguments: [
        EntitlementState.preview, .lapsed(since: now),
    ])
    func firstSyncIsFree(_ state: EntitlementState) async throws {
        let (coordinator, store, gateway) = try make(gate: enforced(state))
        _ = await coordinator.run(trigger: .manual)
        #expect(await gateway.calls == 1)
        #expect(await coordinator.committedSnapshot != nil)
        #expect(await glance(store)?.entitledUntil == nil, "no entitlement to mirror")
    }

    @Test("Entitled: refresh runs, and the commit's glance mirrors the expiry")
    func entitledRefreshesAndMirrors() async throws {
        let cached = CanvasSnapshotFixture.make(generation: 1, fetchedAt: Self.now.addingTimeInterval(-3_600))
        let (coordinator, store, gateway) = try make(gate: enforced(.entitled(until: Self.until)), initialSnapshot: cached)
        _ = await coordinator.run(trigger: .background)
        #expect(await gateway.calls == 1)
        let written = try #require(await glance(store))
        #expect(written.generation == 2 && written.entitledUntil == Self.until)
    }

    @Test("Not enforced (main): a lapse refuses nothing")
    func notEnforcedRefusesNothing() async throws {
        let cached = CanvasSnapshotFixture.make(generation: 1, fetchedAt: Self.now.addingTimeInterval(-3_600))
        let gate = EntitlementGate(isEnforced: false, clock: TestClock(Self.now), state: .lapsed(since: Self.now))
        let (coordinator, _, gateway) = try make(gate: gate, initialSnapshot: cached)
        _ = await coordinator.run(trigger: .manual)
        #expect(await gateway.calls == 1)
    }

    @Test("entitlementDidChange rewrites the glance at once with the gate's expiry, and only when it changed")
    func entitlementChangeRewritesTheGlance() async throws {
        let gate = enforced(.entitled(until: Self.until))
        let (coordinator, store, _) = try make(gate: gate)
        #expect(await coordinator.entitlementDidChange() == false, "nothing committed yet")
        _ = await coordinator.run(trigger: .manual) // the first sync
        #expect(await glance(store)?.entitledUntil == Self.until)
        #expect(await coordinator.entitlementDidChange() == false, "the glance already carries it")

        await gate.update(.lapsed(since: Self.now))
        #expect(await coordinator.entitlementDidChange(), "rewritten")
        let lapsed = try #require(await glance(store))
        #expect(lapsed.entitledUntil == nil && lapsed.generation == 1, "the same snapshot, no expiry: the widgets lock")

        let renewed = Self.until.addingTimeInterval(365 * 24 * 60 * 60)
        await gate.update(.entitled(until: renewed))
        #expect(await coordinator.entitlementDidChange())
        #expect(await glance(store)?.entitledUntil == renewed)
    }

    @Test("A grade opt-in rewrite keeps the mirrored expiry")
    func gradeRewriteKeepsTheExpiry() async throws {
        let (coordinator, store, _) = try make(gate: enforced(.entitled(until: Self.until)), includeGrades: true)
        _ = await coordinator.run(trigger: .manual)
        #expect(await coordinator.updateIncludeGrades(false))
        #expect(await glance(store)?.entitledUntil == Self.until)
        #expect(await coordinator.updateGradeAvailabilityOverrides(["c1": .keptOutsideCanvas]))
        #expect(await glance(store)?.entitledUntil == Self.until)
    }
}

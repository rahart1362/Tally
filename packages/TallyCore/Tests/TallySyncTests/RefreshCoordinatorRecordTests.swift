import Foundation
import Testing
import TallyCanvasAPI
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallySync

/// O5 (PERF-L): the coordinator writes its `RefreshRecord` when a run ends (`RefreshStateStore`),
/// and a coordinator started from that record throttles automatic triggers across launches
/// (`FreshnessRules.shouldStart`, `minAutoRefreshInterval`); a manual refresh always runs. A run
/// that ends after sign-out never writes.
@Suite("RefreshCoordinator: the refresh record is persisted when a run ends", .timeLimit(.minutes(TestTimeBudget.minutes(1))))
struct RefreshCoordinatorRecordTests {
    private let accountKey = AccountKey("refresh-record")

    /// A temp store root, one keyring, the account's snapshot and record stores over it.
    private struct Stores {
        let root: URL
        let keyring: VaultKeyring
        let snapshots: SnapshotStore
        let records: RefreshStateStore
    }

    private func makeStores() throws -> Stores {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tally-refresh-record-\(UUID().uuidString)")
        try ProtectedFile.prepareDirectory(root, excludeFromBackup: true)
        let keyring = VaultKeyring(store: InMemoryVaultKeyStore())
        let sealer = VaultSealer(account: accountKey.rawValue, keyring: keyring, mayCreateKeys: true)
        return Stores(root: root, keyring: keyring, snapshots: SnapshotStore(root: root, accountKey: accountKey, sealer: sealer),
                      records: RefreshStateStore(root: root, accountKey: accountKey, sealer: sealer))
    }

    private func makeCoordinator(_ gateway: any CanvasGateway, _ stores: Stores, clock: TestClock,
                                 initialRecord: RefreshRecord = RefreshRecord(), persisting: Bool = true) -> RefreshCoordinator {
        RefreshCoordinator(gateway: gateway, store: stores.snapshots, clock: clock, initialSnapshot: nil,
                           initialRecord: initialRecord, liveRefreshBudget: .seconds(30), foregroundHardCeiling: .seconds(60),
                           backgroundBudget: .seconds(60), recordStore: persisting ? stores.records : nil)
    }

    @Test("a run that succeeds writes its attempt and its success")
    func aSuccessfulRunIsWritten() async throws {
        let stores = try makeStores()
        let clock = TestClock()
        let coordinator = makeCoordinator(ScriptedGateway(), stores, clock: clock)
        #expect(stores.records.loadRecord() == nil)

        #expect(await coordinator.run(trigger: .launch) == .fresh(at: clock.now()))

        let written = try #require(stores.records.loadRecord())
        #expect(written.lastAttemptAt == clock.now())
        #expect(written.lastSource == .launch)
        #expect(written.lastSuccessAt == clock.now())
        #expect(written.lastFailure == nil && written.inFlightSince == nil)
    }

    @Test("a run that fails writes its attempt and its failure")
    func aFailedRunIsWritten() async throws {
        let stores = try makeStores()
        let clock = TestClock()
        let coordinator = makeCoordinator(FailingGateway(failure: .offline), stores, clock: clock)

        #expect(await coordinator.run(trigger: .foreground) == .offline(showing: nil))

        let written = try #require(stores.records.loadRecord())
        #expect(written.lastAttemptAt == clock.now() && written.lastSource == .foreground)
        #expect(written.lastFailure == .offline && written.inFlightSince == nil)
    }

    @Test("without a record store nothing is written")
    func noStoreNoFile() async throws {
        let stores = try makeStores()
        let coordinator = makeCoordinator(ScriptedGateway(), stores, clock: TestClock(), persisting: false)
        await coordinator.run(trigger: .launch)
        #expect(stores.records.loadRecord() == nil)
    }

    /// The launch sequence O5 exists for: a run ends and is written; the next launch's coordinator
    /// starts from the written record, so its launch trigger waits out `minAutoRefreshInterval`
    /// from that attempt, while a manual refresh runs at once.
    @Test("the next launch's coordinator throttles automatic triggers by the written attempt; manual always runs")
    func theNextLaunchIsThrottledByTheWrittenAttempt() async throws {
        let stores = try makeStores()
        let clock = TestClock()
        await makeCoordinator(ScriptedGateway(), stores, clock: clock).run(trigger: .launch)
        clock.advance(by: .seconds(60))

        // Relaunch: the record comes from disk.
        let relaunched = ScriptedGateway()
        let persisted = try #require(stores.records.loadRecord())
        let coordinator = makeCoordinator(relaunched, stores, clock: clock,
                                          initialRecord: RefreshStateStore.startingRecord(persisted: persisted,
                                                                                          committedDataFetchedAt: nil))
        await coordinator.run(trigger: .launch)
        await coordinator.run(trigger: .foreground)
        await coordinator.run(trigger: .background)
        #expect(await relaunched.calls == 0, "an automatic trigger ran 60 s after the last attempt")

        await coordinator.run(trigger: .manual)
        #expect(await relaunched.calls == 1, "a manual refresh must always run")

        // Once the interval has passed since the last attempt, the launch trigger runs again.
        clock.advance(by: TallyConfig.minAutoRefreshInterval)
        await coordinator.run(trigger: .launch)
        #expect(await relaunched.calls == 2)
    }

    @Test("with no record written, the next launch refreshes (today's behaviour)")
    func noRecordMeansTheLaunchRefreshes() async throws {
        let stores = try makeStores()
        let clock = TestClock()
        let gateway = ScriptedGateway()
        let coordinator = makeCoordinator(gateway, stores, clock: clock,
                                          initialRecord: RefreshStateStore.startingRecord(
                                              persisted: stores.records.loadRecord(), committedDataFetchedAt: clock.now()))
        await coordinator.run(trigger: .launch)
        #expect(await gateway.calls == 1)
    }

    /// Sign-out bumps the epoch, then purges the store. A run still in flight then must never
    /// write: the write would re-create the purged account's directory and mint it a new key.
    @Test("a run that ends after sign-out's epoch bump and purge writes nothing")
    func aRunEndingAfterSignOutNeverWrites() async throws {
        let stores = try makeStores()
        let gateway = ScriptedGateway(holdUntilReleased: true, honorsCancellation: false)
        let coordinator = makeCoordinator(gateway, stores, clock: TestClock())
        let running = Task { await coordinator.run(trigger: .launch) }
        #expect(await eventually { await gateway.calls == 1 })

        await coordinator.bumpEpochAndCancel()
        try AccountPurger.purge(accountKey: accountKey, root: stores.root, keyring: stores.keyring)
        await gateway.release()
        _ = await running.value
        #expect(await eventually { await gateway.returned.count == 1 }, "the held fetch never ended")
        try await Task.sleep(for: .milliseconds(50)) // the run's own task winds down

        let accountDirectory = StoreLayout(root: stores.root, accountKey: accountKey).accountDirectory
        #expect(!FileManager.default.fileExists(atPath: accountDirectory.path),
                "a run that ended after sign-out re-created the purged account directory")
        #expect(stores.records.loadRecord() == nil)
    }

    @Test("an abandoned run still writes its attempt, so the next launch is throttled by it")
    func anAbandonedRunWritesItsAttempt() async throws {
        let stores = try makeStores()
        let clock = TestClock()
        let gateway = ScriptedGateway(holdUntilReleased: true)
        let coordinator = makeCoordinator(gateway, stores, clock: clock)
        let caller = Task { await coordinator.run(trigger: .launch) }
        #expect(await eventually { await gateway.calls == 1 })
        caller.cancel()
        _ = await caller.value
        #expect(await eventually { stores.records.loadRecord() != nil }, "the abandoned run wrote nothing")

        let written = try #require(stores.records.loadRecord())
        #expect(written.lastAttemptAt == clock.now() && written.lastSource == .launch)
        #expect(written.lastFailure == nil && written.lastSuccessAt == nil && written.inFlightSince == nil)
    }
}

/// Always fails with `failure`.
private struct FailingGateway: CanvasGateway {
    let failure: RefreshFailure
    func fetchSnapshot(previous: CanvasSnapshot?, now: Date) async throws -> CanvasSnapshot { throw failure }
}

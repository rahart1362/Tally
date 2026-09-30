import Foundation
import Testing
import TallyTestSupport
@testable import TallyStore
@testable import TallyDomain

/// O5 (PERF-L): `refresh-state.sealed`, one account's `RefreshRecord`, sealed with the app key in
/// the account directory. Rederivable: anything unreadable is discarded and reads as "no attempt
/// known".
@Suite("RefreshStateStore: the account's refresh record, sealed")
struct RefreshStateStoreTests {
    let accountKey = AccountKey("acct-refresh-state")
    let anchor = Date(timeIntervalSince1970: 1_790_600_400)

    private func makeSealer(_ keys: InMemoryVaultKeyStore = InMemoryVaultKeyStore(), mayCreateKeys: Bool = true) -> VaultSealer {
        VaultSealer(account: accountKey.rawValue, keyring: VaultKeyring(store: keys), mayCreateKeys: mayCreateKeys)
    }

    private func record(attemptAt: Date, trigger: RefreshTrigger = .launch, outcome: Result<Date, RefreshFailure>) -> RefreshRecord {
        var record = RefreshRecord()
        record.began(trigger, at: attemptAt)
        switch outcome {
        case .success(let fetchedAt): record.succeeded(dataFetchedAt: fetchedAt)
        case .failure(let failure): record.failed(failure)
        }
        return record
    }

    @Test func absentBeforeAnySave() throws {
        let store = RefreshStateStore(root: try tempStoreDirectory(), accountKey: accountKey, sealer: makeSealer())
        #expect(store.load() == .absent)
        #expect(store.loadRecord() == nil)
    }

    @Test(arguments: [Result<Date, RefreshFailure>.success(Date(timeIntervalSince1970: 1_790_600_000)), .failure(.offline)])
    func saveThenLoadRoundTrips(outcome: Result<Date, RefreshFailure>) throws {
        let root = try tempStoreDirectory()
        let store = RefreshStateStore(root: root, accountKey: accountKey, sealer: makeSealer())
        let saved = record(attemptAt: anchor, trigger: .foreground, outcome: outcome)
        try store.save(saved)
        #expect(store.load() == .loaded(saved))
        let url = StoreLayout(root: root, accountKey: accountKey).url(for: .refreshState)
        #expect(url.lastPathComponent == "refresh-state.sealed")
        #expect(url.deletingLastPathComponent() == StoreLayout(root: root, accountKey: accountKey).accountDirectory)
    }

    @Test func theFileIsSealedNotPlainJSON() throws {
        let root = try tempStoreDirectory()
        try RefreshStateStore(root: root, accountKey: accountKey, sealer: makeSealer())
            .save(record(attemptAt: anchor, outcome: .failure(.server)))
        let bytes = try #require(try ProtectedFile.read(StoreLayout(root: root, accountKey: accountKey).url(for: .refreshState)))
        #expect(try SealedBlobHeader.decode(from: bytes).file == .refreshState)
        #expect(String(decoding: bytes, as: UTF8.self).contains("lastAttemptAt") == false)
    }

    @Test func anUndecodablePayloadIsDiscarded() throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let url = StoreLayout(root: root, accountKey: accountKey).url(for: .refreshState)
        try ProtectedFile.prepareDirectory(url.deletingLastPathComponent(), excludeFromBackup: true)
        try ProtectedFile.atomicWrite(try sealer.seal(Data("garbage".utf8), file: .refreshState), to: url, excludeFromBackup: true)

        #expect(RefreshStateStore(root: root, accountKey: accountKey, sealer: sealer).load() == .absent)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func anotherVersionIsDiscarded() throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let url = StoreLayout(root: root, accountKey: accountKey).url(for: .refreshState)
        try ProtectedFile.prepareDirectory(url.deletingLastPathComponent(), excludeFromBackup: true)
        let future = Data(#"{"version":2,"record":{}}"#.utf8)
        try ProtectedFile.atomicWrite(try sealer.seal(future, file: .refreshState), to: url, excludeFromBackup: true)

        #expect(RefreshStateStore(root: root, accountKey: accountKey, sealer: sealer).load() == .absent)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aRecordSealedUnderAShreddedKeyReadsAsAbsent() throws {
        let root = try tempStoreDirectory()
        let keys = InMemoryVaultKeyStore()
        try RefreshStateStore(root: root, accountKey: accountKey, sealer: makeSealer(keys))
            .save(record(attemptAt: anchor, outcome: .success(anchor)))
        try VaultKeyring(store: keys).shred(account: accountKey.rawValue)
        #expect(RefreshStateStore(root: root, accountKey: accountKey, sealer: makeSealer(keys)).load() == .absent)
    }

    @Test func aProcessThatDoesNotOwnTheStoreCannotWriteIt() throws {
        let store = RefreshStateStore(root: try tempStoreDirectory(), accountKey: accountKey,
                                      sealer: makeSealer(mayCreateKeys: false), isOwner: false)
        #expect(throws: VaultError.readOnlyProcess) { try store.save(record(attemptAt: anchor, outcome: .success(anchor))) }
    }

    /// The layout's file list is what the foreground orphan sweep keeps: a file missing from it
    /// would be deleted on the next launch.
    @Test func theOrphanSweepKeepsTheRecord() async throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let saved = record(attemptAt: anchor, outcome: .success(anchor))
        try RefreshStateStore(root: root, accountKey: accountKey, sealer: sealer).save(saved)
        #expect(StoreLayout.allFileNames.contains("refresh-state.sealed"))

        await SnapshotStore(root: root, accountKey: accountKey, sealer: sealer).sweepOrphanedTempFiles()
        #expect(RefreshStateStore(root: root, accountKey: accountKey, sealer: sealer).load() == .loaded(saved))
    }

    // MARK: - The record a launch starts from

    @Test func withNoRecordTheCommittedDataIsTheLastSuccessAndNoAttemptIsKnown() {
        let record = RefreshStateStore.startingRecord(persisted: nil, committedDataFetchedAt: anchor)
        #expect(record.lastSuccessAt == anchor)
        #expect(record.lastAttemptAt == nil)
        #expect(FreshnessRules.shouldStart(.launch, record: record, now: anchor.addingTimeInterval(1)),
                "with no attempt known, the launch refresh must run")
    }

    @Test func aPersistedRecordIsKeptWhenItKnowsTheCommittedData() {
        // A success at the committed data, then a later attempt that failed offline.
        var persisted = record(attemptAt: anchor, outcome: .success(anchor))
        persisted.began(.foreground, at: anchor.addingTimeInterval(60))
        persisted.failed(.offline)

        let started = RefreshStateStore.startingRecord(persisted: persisted, committedDataFetchedAt: anchor)
        #expect(started == persisted)
        #expect(FreshnessRules.state(of: started, now: anchor.addingTimeInterval(90)) == .offline(showing: anchor))
        #expect(!FreshnessRules.shouldStart(.launch, record: started, now: anchor.addingTimeInterval(120)),
                "an attempt 60 s ago must throttle the launch refresh")
        #expect(FreshnessRules.shouldStart(.manual, record: started, now: anchor.addingTimeInterval(120)))
    }

    @Test func aRecordWithNoSuccessTakesTheCommittedDataAsItsSuccess() {
        let persisted = record(attemptAt: anchor.addingTimeInterval(60), outcome: .failure(.offline))
        let started = RefreshStateStore.startingRecord(persisted: persisted, committedDataFetchedAt: anchor)
        #expect(started.lastSuccessAt == anchor && started.lastFailure == nil)
        #expect(started.lastAttemptAt == anchor.addingTimeInterval(60), "the attempt must survive")
    }

    @Test func committedDataNewerThanTheRecordCountsAsTheLastSuccess() {
        // The app stopped between a commit and the record's write: the record is one run behind.
        let behind = record(attemptAt: anchor, outcome: .failure(.server))
        let newer = anchor.addingTimeInterval(600)
        let started = RefreshStateStore.startingRecord(persisted: behind, committedDataFetchedAt: newer)
        #expect(started.lastSuccessAt == newer)
        #expect(started.lastFailure == nil)
        #expect(started.lastAttemptAt == anchor)
    }

    @Test func noInFlightMarkSurvivesALaunch() {
        var inFlight = RefreshRecord()
        inFlight.began(.manual, at: anchor)
        let started = RefreshStateStore.startingRecord(persisted: inFlight, committedDataFetchedAt: nil)
        #expect(started.inFlightSince == nil)
        #expect(started.lastAttemptAt == anchor)
    }
}

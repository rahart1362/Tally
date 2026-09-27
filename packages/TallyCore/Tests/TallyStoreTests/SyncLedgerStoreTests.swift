import Foundation
import Testing
import TallyTestSupport
@testable import TallyStore
@testable import TallyDomain

@Suite("SyncLedgerStore: rederivable side-effect ledger")
struct SyncLedgerStoreTests {
    let accountKey = AccountKey("acct-ledger")

    private func makeSealer(_ keys: InMemoryVaultKeyStore = InMemoryVaultKeyStore()) -> VaultSealer {
        VaultSealer(account: accountKey.rawValue, keyring: VaultKeyring(store: keys), mayCreateKeys: true)
    }

    @Test func absentBeforeAnySave() async throws {
        let store = SyncLedgerStore(root: try tempStoreDirectory(), accountKey: accountKey, sealer: makeSealer())
        #expect(await store.load() == .absent)
    }

    @Test func saveThenLoadRoundTrips() async throws {
        let store = SyncLedgerStore(root: try tempStoreDirectory(), accountKey: accountKey, sealer: makeSealer())
        let ledger = SyncLedger(notifications: ["tally.acct.due.1204400.24h": "hash-a"],
                                 calendarEvents: ["tally://acct/assignment/1204400": CalendarLedgerEntry(eventIdentifier: "EK-1", contentHash: "hash-b")])
        try await store.save(ledger)
        #expect(await store.load() == .loaded(ledger))
    }

    /// Unlike `UserState`, the ledger is entirely rederivable (a reconciler rebuilds it by
    /// re-scanning the OS state), so a corrupt payload discards and rebuilds rather than resetting
    /// and telling the user.
    @Test func corruptPayloadDiscardsAndRebuildsAndRemovesTheFile() async throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let layout = StoreLayout(root: root, accountKey: accountKey)
        try ProtectedFile.prepareDirectory(layout.accountDirectory, excludeFromBackup: true)
        try ProtectedFile.atomicWrite(try sealer.seal(Data("garbage".utf8), file: .ledger), to: layout.url(for: .ledger), excludeFromBackup: true)

        let store = SyncLedgerStore(root: root, accountKey: accountKey, sealer: sealer)
        #expect(await store.load() == .unavailable(.discardAndRebuild))
        #expect(!FileManager.default.fileExists(atPath: layout.url(for: .ledger).path))
    }
}

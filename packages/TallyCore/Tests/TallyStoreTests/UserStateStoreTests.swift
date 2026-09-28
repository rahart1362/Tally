import Foundation
import Testing
import TallyTestSupport
@testable import TallyStore
@testable import TallyDomain

@Suite("UserStateStore: versioned migrations and reset-and-tell")
struct UserStateStoreTests {
    let accountKey = AccountKey("acct-userstate")

    private func makeSealer(_ keys: InMemoryVaultKeyStore = InMemoryVaultKeyStore()) -> VaultSealer {
        VaultSealer(account: accountKey.rawValue, keyring: VaultKeyring(store: keys), mayCreateKeys: true)
    }

    @Test func absentBeforeAnySave() async throws {
        let store = UserStateStore(root: try tempStoreDirectory(), accountKey: accountKey, sealer: makeSealer())
        #expect(await store.load() == .absent)
    }

    @Test func saveThenLoadRoundTrips() async throws {
        let store = UserStateStore(root: try tempStoreDirectory(), accountKey: accountKey, sealer: makeSealer())
        let manual = ManualClassTime(courseID: "101", weekday: 2, startMinutesFromMidnight: 9 * 60, endMinutesFromMidnight: 10 * 60)
        let state = UserState(showGradesInGlance: true, hideCourseNamesInNotifications: true, manualClassTimes: [manual])
        try await store.save(state)
        #expect(await store.load() == .loaded(state))
    }

    /// The one real migration this store ships (WP-C02 acceptance): a v1 payload (no
    /// `hideCourseNamesInNotifications`) upgrades to the current schema with a safe default.
    @Test func migratesV1PayloadToCurrentSchema() async throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let layout = StoreLayout(root: root, accountKey: accountKey)
        try ProtectedFile.prepareDirectory(layout.accountDirectory, excludeFromBackup: true)

        let manual = ManualClassTime(id: "fixed-id", courseID: "202", weekday: 3, startMinutesFromMidnight: 480, endMinutesFromMidnight: 540)
        let v1JSON: [String: Any] = [
            "schemaVersion": 1,
            "showGradesInGlance": true,
            "manualClassTimes": [[
                "id": manual.id, "courseID": manual.courseID.rawValue,
                "weekday": manual.weekday, "startMinutesFromMidnight": manual.startMinutesFromMidnight,
                "endMinutesFromMidnight": manual.endMinutesFromMidnight,
            ]],
        ]
        let v1Data = try JSONSerialization.data(withJSONObject: v1JSON)
        try ProtectedFile.atomicWrite(try sealer.seal(v1Data, file: .userState), to: layout.url(for: .userState), excludeFromBackup: true)

        let store = UserStateStore(root: root, accountKey: accountKey, sealer: sealer)
        guard case .loaded(let migrated) = await store.load() else { Issue.record("expected a migrated UserState"); return }
        #expect(migrated.schemaVersion == UserState.currentSchemaVersion)
        #expect(migrated.showGradesInGlance == true)
        #expect(migrated.hideCourseNamesInNotifications == false, "v1 never had this field; it defaults to the private choice")
        #expect(migrated.manualClassTimes == [manual])
    }

    /// v2 → v3 (owner decision 2026-09-27): every v2 field survives and the new "What changed"
    /// threshold starts at the 0.5 pt default everywhere.
    @Test func migratesV2PayloadAddingDefaultDigestThresholds() async throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let layout = StoreLayout(root: root, accountKey: accountKey)
        try ProtectedFile.prepareDirectory(layout.accountDirectory, excludeFromBackup: true)
        let v2JSON: [String: Any] = [
            "schemaVersion": 2, "showGradesInGlance": false,
            "hideCourseNamesInNotifications": true, "manualClassTimes": [],
        ]
        let v2Data = try JSONSerialization.data(withJSONObject: v2JSON)
        try ProtectedFile.atomicWrite(try sealer.seal(v2Data, file: .userState), to: layout.url(for: .userState), excludeFromBackup: true)

        let store = UserStateStore(root: root, accountKey: accountKey, sealer: sealer)
        guard case .loaded(let migrated) = await store.load() else { Issue.record("expected a migrated UserState"); return }
        #expect(migrated.schemaVersion == 3)
        #expect(migrated.hideCourseNamesInNotifications == true)
        #expect(migrated.digestThresholds == .default)
        #expect(migrated.digestThresholds.threshold(for: "51845") == .points(0.5))
    }

    @Test func customDigestThresholdsRoundTrip() async throws {
        let store = UserStateStore(root: try tempStoreDirectory(), accountKey: accountKey, sealer: makeSealer())
        let state = UserState(digestThresholds: DigestThresholds(global: .all, perCourse: ["51845": .points(2)]))
        try await store.save(state)
        #expect(await store.load() == .loaded(state))
    }

    /// Undecodable and not rederivable from Canvas: reset to empty and tell the user once, per
    /// encryption.md's disposition table — but the on-disk file must actually be removed so a
    /// fresh empty state can be saved afterwards.
    @Test func corruptPayloadResetsAndTellsAndRemovesTheFile() async throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let layout = StoreLayout(root: root, accountKey: accountKey)
        try ProtectedFile.prepareDirectory(layout.accountDirectory, excludeFromBackup: true)
        try ProtectedFile.atomicWrite(try sealer.seal(Data("not json".utf8), file: .userState),
                                      to: layout.url(for: .userState), excludeFromBackup: true)

        let store = UserStateStore(root: root, accountKey: accountKey, sealer: sealer)
        #expect(await store.load() == .unavailable(.resetUserStateAndTell))
        #expect(!FileManager.default.fileExists(atPath: layout.url(for: .userState).path))
    }

    /// A schema version newer than this build knows must NEVER be deleted: it may have been
    /// written by a newer app version, and there is no data to lose by waiting.
    @Test func futureSchemaVersionIsKeptNotDeleted() async throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let layout = StoreLayout(root: root, accountKey: accountKey)
        try ProtectedFile.prepareDirectory(layout.accountDirectory, excludeFromBackup: true)
        let future = try JSONSerialization.data(withJSONObject: ["schemaVersion": 99])
        try ProtectedFile.atomicWrite(try sealer.seal(future, file: .userState), to: layout.url(for: .userState), excludeFromBackup: true)

        let store = UserStateStore(root: root, accountKey: accountKey, sealer: sealer)
        #expect(await store.load() == .unavailable(.keepAndReport))
        #expect(FileManager.default.fileExists(atPath: layout.url(for: .userState).path), "must not delete data from a newer app version")
    }
}

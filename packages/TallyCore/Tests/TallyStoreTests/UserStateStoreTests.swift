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
        #expect(migrated.schemaVersion == UserState.currentSchemaVersion)
        #expect(migrated.hideCourseNamesInNotifications == true)
        #expect(migrated.digestThresholds == .default)
        #expect(migrated.digestThresholds.threshold(for: "51845") == .points(0.5))
    }

    /// v3 → v4 (M3-A O3, M3-C O1): every v3 field survives, and the screens' local state starts empty.
    @Test func migratesV3PayloadAddingEmptyScreenState() async throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let layout = StoreLayout(root: root, accountKey: accountKey)
        try ProtectedFile.prepareDirectory(layout.accountDirectory, excludeFromBackup: true)
        let thresholds = DigestThresholds(global: .all)
        var v3JSON = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            UserState(showGradesInGlance: true, hideCourseNamesInNotifications: true, digestThresholds: thresholds))) as? [String: Any])
        v3JSON["schemaVersion"] = 3
        for key in ["courseOrder", "doneAssignments", "reminderTipDismissedUntil"] { v3JSON[key] = nil }
        let v3Data = try JSONSerialization.data(withJSONObject: v3JSON)
        try ProtectedFile.atomicWrite(try sealer.seal(v3Data, file: .userState), to: layout.url(for: .userState), excludeFromBackup: true)

        let store = UserStateStore(root: root, accountKey: accountKey, sealer: sealer)
        guard case .loaded(let migrated) = await store.load() else { Issue.record("expected a migrated UserState"); return }
        #expect(migrated.schemaVersion == UserState.currentSchemaVersion)
        #expect(migrated.showGradesInGlance && migrated.hideCourseNamesInNotifications)
        #expect(migrated.digestThresholds == thresholds)
        #expect(migrated.courseOrder.isEmpty && migrated.doneAssignments.isEmpty && migrated.reminderTipDismissedUntil == nil)
    }

    /// v4 → v5 (plan 08 XG-04): every v4 field survives, and every course starts Automatic (no
    /// "grades kept outside Canvas" override).
    @Test func migratesV4PayloadKeepingEveryFieldWithNoOverrides() async throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let layout = StoreLayout(root: root, accountKey: accountKey)
        try ProtectedFile.prepareDirectory(layout.accountDirectory, excludeFromBackup: true)
        let manual = ManualClassTime(id: "fixed-id", courseID: "202", weekday: 3, startMinutesFromMidnight: 480, endMinutesFromMidnight: 540)
        let v4State = UserState(showGradesInGlance: true, hideCourseNamesInNotifications: true, manualClassTimes: [manual],
                                digestThresholds: DigestThresholds(global: .all, perCourse: ["51845": .points(2)]),
                                courseOrder: ["51842", "51840"], doneAssignments: ["9001"],
                                reminderTipDismissedUntil: Date(timeIntervalSince1970: 1_800_000_000))
        var v4JSON = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(v4State)) as? [String: Any])
        v4JSON["schemaVersion"] = 4
        v4JSON["gradesOutsideCanvasOverride"] = nil
        let v4Data = try JSONSerialization.data(withJSONObject: v4JSON)
        try ProtectedFile.atomicWrite(try sealer.seal(v4Data, file: .userState), to: layout.url(for: .userState), excludeFromBackup: true)

        let store = UserStateStore(root: root, accountKey: accountKey, sealer: sealer)
        guard case .loaded(let migrated) = await store.load() else { Issue.record("expected a migrated UserState"); return }
        #expect(migrated.schemaVersion == 5 && UserState.currentSchemaVersion == 5)
        #expect(migrated == v4State, "every v4 field kept, and no override")
        #expect(migrated.gradesOutsideCanvasOverride.isEmpty && migrated.gradeAvailabilityOverrides.isEmpty)
    }

    /// v5 round trip, and the persisted contract: `GradeAvailabilityOverride`'s raw values, keyed
    /// by course ID (the XG-01 report's handoff note).
    @Test func gradeAvailabilityOverridesRoundTripByRawValue() async throws {
        let store = UserStateStore(root: try tempStoreDirectory(), accountKey: accountKey, sealer: makeSealer())
        let state = UserState(courseOrder: ["77306"],
                              gradeAvailabilityOverrides: ["77301": .inCanvas, "77306": .keptOutsideCanvas])
        #expect(state.gradesOutsideCanvasOverride == ["77301": "inCanvas", "77306": "keptOutsideCanvas"])
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        #expect(json["gradesOutsideCanvasOverride"] as? [String: String] == ["77301": "inCanvas", "77306": "keptOutsideCanvas"])
        try await store.save(state)
        guard case .loaded(let loaded) = await store.load() else { Issue.record("expected the saved UserState"); return }
        #expect(loaded == state)
        #expect(loaded.gradeAvailabilityOverrides == ["77301": .inCanvas, "77306": .keptOutsideCanvas])

        // Automatic removes the entry; the typed setter writes raw values only.
        var edited = loaded
        edited.gradeAvailabilityOverrides["77301"] = nil
        edited.gradeAvailabilityOverrides["77302"] = .inCanvas
        #expect(edited.gradesOutsideCanvasOverride == ["77302": "inCanvas", "77306": "keptOutsideCanvas"])
    }

    /// A raw value this build does not know reads as Automatic for that course; the rest of the
    /// state still loads (a failed decode would reset every setting).
    @Test func anUnknownOverrideValueReadsAsAutomatic() async throws {
        let root = try tempStoreDirectory()
        let sealer = makeSealer()
        let layout = StoreLayout(root: root, accountKey: accountKey)
        try ProtectedFile.prepareDirectory(layout.accountDirectory, excludeFromBackup: true)
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            UserState(showGradesInGlance: true, courseOrder: ["2"]))) as? [String: Any])
        json["gradesOutsideCanvasOverride"] = ["1": "aNewerAnswer", "2": "inCanvas"]
        try ProtectedFile.atomicWrite(try sealer.seal(try JSONSerialization.data(withJSONObject: json), file: .userState),
                                      to: layout.url(for: .userState), excludeFromBackup: true)

        let store = UserStateStore(root: root, accountKey: accountKey, sealer: sealer)
        guard case .loaded(let loaded) = await store.load() else { Issue.record("expected the UserState to load"); return }
        #expect(loaded.showGradesInGlance && loaded.courseOrder == ["2"])
        #expect(loaded.gradeAvailabilityOverrides == ["2": .inCanvas], "course 1 is Automatic")
        #expect(loaded.gradesOutsideCanvasOverride["1"] == "aNewerAnswer", "the stored value is left as it was")
    }

    @Test func screenStateRoundTrips() async throws {
        let store = UserStateStore(root: try tempStoreDirectory(), accountKey: accountKey, sealer: makeSealer())
        let state = UserState(courseOrder: ["51842", "51840"], doneAssignments: ["9001", "9002"],
                              reminderTipDismissedUntil: Date(timeIntervalSince1970: 1_800_000_000))
        try await store.save(state)
        #expect(await store.load() == .loaded(state))
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

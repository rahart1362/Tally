import Foundation
import Testing
@testable import TallyStore

/// AGE-1 (EB-01(c)): `age-request.json` carries exactly one field, the date of the last request —
/// never an age value. `significant-change-state.json` carries two non-age values (the app's own
/// version string and StoreKit's age-rating code).
@Suite("AgeRequestRecordStore / SignificantChangeVersionStore")
struct AgeAssuranceStoreTests {
    @Test("no file: nil, and nothing is created by reading")
    func missingFileIsNil() throws {
        let store = AgeRequestRecordStore(root: try tempStoreDirectory())
        #expect(store.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test("save then load round-trips the one field exactly")
    func roundTrips() throws {
        let store = AgeRequestRecordStore(root: try tempStoreDirectory())
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        try store.save(AgeRequestRecord(lastRequestedAt: date))
        #expect(store.load() == AgeRequestRecord(lastRequestedAt: date))
    }

    @Test("a second save overwrites the first, never appends")
    func secondSaveOverwrites() throws {
        let store = AgeRequestRecordStore(root: try tempStoreDirectory())
        try store.save(AgeRequestRecord(lastRequestedAt: Date(timeIntervalSince1970: 1)))
        try store.save(AgeRequestRecord(lastRequestedAt: Date(timeIntervalSince1970: 2)))
        #expect(store.load() == AgeRequestRecord(lastRequestedAt: Date(timeIntervalSince1970: 2)))
    }

    @Test("reset removes the file: the one field this feature may persist is also the one it can fully erase")
    func resetRemovesTheFile() throws {
        let store = AgeRequestRecordStore(root: try tempStoreDirectory())
        try store.save(AgeRequestRecord(lastRequestedAt: Date()))
        store.reset()
        #expect(store.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test("an undecodable file reads as nil, not a crash")
    func undecodableFileIsNil() throws {
        let root = try tempStoreDirectory()
        let store = AgeRequestRecordStore(root: root)
        try ProtectedFile.atomicWrite(Data("not json".utf8), to: store.fileURL, excludeFromBackup: true)
        #expect(store.load() == nil)
    }

    @Test("SignificantChangeVersionState round-trips both non-age fields")
    func versionStateRoundTrips() throws {
        let store = SignificantChangeVersionStore(root: try tempStoreDirectory())
        let state = SignificantChangeVersionState(lastAcknowledgedSignificantChangeVersion: "1.4.0", lastKnownAgeRatingCode: 4)
        try store.save(state)
        #expect(store.load() == state)
    }

    @Test("the two stores live in separate files, side by side")
    func storesAreIndependentFiles() throws {
        let root = try tempStoreDirectory()
        #expect(AgeRequestRecordStore(root: root).fileURL != SignificantChangeVersionStore(root: root).fileURL)
    }
}

import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain
@testable import TallyStore

/// `accounts.json` (architecture.md §3.2; encryption.md §3.2): the account list the launch
/// bootstrapper reads first (perf-app-runtime.md §2.4 L3) and sign-in writes (S3).
@Suite("AccountDirectoryStore: accounts.json")
struct AccountDirectoryStoreTests {
    private let northfield = AccountRecord.derived(host: "canvas.northfield.example", canvasUserID: "4820117",
                                                   clientID: "10000000000042", displayLabel: "Northfield State University")
    private let riverside = AccountRecord.derived(host: "canvas.riverside.example", canvasUserID: "77",
                                                  clientID: "10000000000077", displayLabel: "Riverside College")

    @Test("no file: absent, and no active account")
    func missingFileIsAbsent() throws {
        let store = AccountDirectoryStore(root: try tempStoreDirectory())
        #expect(store.load() == .absent)
        #expect(store.activeAccount() == nil)
    }

    @Test("activate writes the record and makes it active; it reads back exactly")
    func activateRoundTrips() throws {
        let store = AccountDirectoryStore(root: try tempStoreDirectory())
        try store.activate(northfield)
        #expect(store.activeAccount() == northfield)
        #expect(store.load() == .loaded(AccountDirectory(accounts: [northfield], activeAccountKey: northfield.accountKey)))
        #expect(northfield.accountKey == AccountKey.derive(host: "canvas.northfield.example", userID: "4820117"))
    }

    @Test("signing in to the same account again replaces its record instead of duplicating it")
    func reactivatingTheSameAccountDoesNotDuplicate() throws {
        let store = AccountDirectoryStore(root: try tempStoreDirectory())
        try store.activate(northfield)
        try store.activate(riverside)
        try store.activate(northfield)
        guard case .loaded(let directory) = store.load() else {
            Issue.record("accounts.json did not load")
            return
        }
        #expect(directory.accounts.map(\.accountKey) == [riverside.accountKey, northfield.accountKey])
        #expect(directory.active == northfield)
    }

    @Test("remove forgets the account; removing the last one deletes the file")
    func removeForgetsTheAccount() throws {
        let store = AccountDirectoryStore(root: try tempStoreDirectory())
        try store.activate(riverside)
        try store.activate(northfield)
        try store.remove(northfield.accountKey)
        guard case .loaded(let directory) = store.load() else {
            Issue.record("accounts.json did not load")
            return
        }
        #expect(directory.accounts == [riverside])
        #expect(directory.active == nil, "the removed account was the active one")
        try store.remove(riverside.accountKey)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(store.load() == .absent)
        try store.remove(riverside.accountKey) // idempotent
    }

    @Test("an undecodable or future-schema file is absent, never a crash")
    func corruptFileIsAbsent() throws {
        let root = try tempStoreDirectory()
        let store = AccountDirectoryStore(root: root)
        try ProtectedFile.atomicWrite(Data("{not json".utf8), to: store.fileURL, excludeFromBackup: true)
        #expect(store.load() == .absent)
        let future = #"{"schemaVersion": 99, "accounts": [], "activeAccountKey": null}"#
        try ProtectedFile.atomicWrite(Data(future.utf8), to: store.fileURL, excludeFromBackup: true)
        #expect(store.load() == .absent)
        try store.activate(northfield) // a later sign-in replaces it
        #expect(store.activeAccount() == northfield)
    }

    @Test("the file carries no tokens and no student name: exactly the record's five keys")
    func fileCarriesNoStudentContent() throws {
        let store = AccountDirectoryStore(root: try tempStoreDirectory())
        try store.activate(northfield)
        let data = try Data(contentsOf: store.fileURL)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["schemaVersion", "accounts", "activeAccountKey"])
        let accounts = try #require(object["accounts"] as? [[String: Any]])
        let first = try #require(accounts.first)
        #expect(Set(first.keys) == ["accountKey", "host", "canvasUserID", "clientID", "displayLabel"])
    }
}

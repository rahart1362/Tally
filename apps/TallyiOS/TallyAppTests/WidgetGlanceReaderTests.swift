import Foundation
import Testing
import TallyDomain
import TallyStore
import TallyTestSupport
@testable import TallyGlance

/// Plan 06 step 11 (W1, W3): the widget reads the glance and only the glance, never writes, and
/// degrades to a message, never a crash, when it cannot read.
@Suite("Widget glance reader")
struct WidgetGlanceReaderTests {
    @Test("reads the glance the app committed, with the widget's keys alone")
    func readsTheCommittedGlance() async throws {
        let fixture = GlanceStoreFixture()
        defer { fixture.remove() }
        let account = GlanceStoreFixture.account("1")
        let committed = try await fixture.commit(account)

        let result = await GlanceReader(storeRoot: fixture.root, keyStore: fixture.widgetKeys).read()

        #expect(result == .loaded(committed))
    }

    @Test("cannot open the snapshot: its key is app-audience, which the widget's key store never has")
    func cannotOpenTheSnapshot() async throws {
        let fixture = GlanceStoreFixture()
        defer { fixture.remove() }
        let account = GlanceStoreFixture.account("1")
        try await fixture.commit(account)
        let before = fixture.contents()

        let widgetStore = SnapshotStore(
            root: fixture.root, accountKey: account,
            sealer: VaultSealer(account: account.rawValue, keyring: VaultKeyring(store: fixture.widgetKeys), mayCreateKeys: false),
            isOwner: false)
        let snapshot = await widgetStore.loadSnapshot()

        #expect(snapshot == .unavailable(.discardAndRebuild)) // keyMissing
        #expect(fixture.contents() == before, "the widget changed a store file")
    }

    @Test("no container is unavailable; no account directory is signed out")
    func noContainerOrNoAccount() async throws {
        let fixture = GlanceStoreFixture()
        defer { fixture.remove() }
        #expect(await GlanceReader(storeRoot: nil, keyStore: fixture.widgetKeys).read() == .unavailable)
        #expect(await GlanceReader(storeRoot: fixture.root, keyStore: fixture.widgetKeys).read() == .noAccount)

        // Hidden entries and plain files under accounts/ are not accounts.
        let accounts = fixture.root.appendingPathComponent("accounts", isDirectory: true)
        try FileManager.default.createDirectory(at: accounts.appendingPathComponent(".tmp-dir"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: accounts.appendingPathComponent("stray-file"))
        #expect(await GlanceReader(storeRoot: fixture.root, keyStore: fixture.widgetKeys).read() == .noAccount)
    }

    @Test("an account before its first commit has no glance")
    func accountBeforeFirstCommit() async throws {
        let fixture = GlanceStoreFixture()
        defer { fixture.remove() }
        try await fixture.ownerStore(GlanceStoreFixture.account("1")).prepare()

        #expect(await GlanceReader(storeRoot: fixture.root, keyStore: fixture.widgetKeys).read() == .noGlance)
    }

    @Test("a locked Keychain is locked and a Keychain failure is unavailable; neither deletes anything")
    func keychainFailuresDegrade() async throws {
        let fixture = GlanceStoreFixture()
        defer { fixture.remove() }
        try await fixture.commit(GlanceStoreFixture.account("1"))
        let before = fixture.contents()
        let widgetKeys = fixture.widgetKeys

        widgetKeys.failure = .protectedDataUnavailable
        #expect(await GlanceReader(storeRoot: fixture.root, keyStore: widgetKeys).read() == .locked)
        // errSecMissingEntitlement (-34018): the App Group access group without a Team ID (GL-02).
        widgetKeys.failure = .storage(code: -34018)
        #expect(await GlanceReader(storeRoot: fixture.root, keyStore: widgetKeys).read() == .unavailable)

        #expect(fixture.contents() == before, "the widget changed a store file")
    }

    @Test("a purged account (keys shredded, files left) is skipped; the live account's glance is read")
    func purgedAccountIsSkipped() async throws {
        let fixture = GlanceStoreFixture()
        defer { fixture.remove() }
        let live = GlanceStoreFixture.account("live")
        let purged = GlanceStoreFixture.account("purged")
        let liveGlance = try await fixture.commit(live)
        try await fixture.commit(purged, fetchedAt: Date(timeIntervalSince1970: 1_790_700_000))
        try VaultKeyring(store: fixture.appKeys).shred(account: purged.rawValue)
        let before = fixture.contents()

        #expect(await GlanceReader(storeRoot: fixture.root, keyStore: fixture.widgetKeys).read() == .loaded(liveGlance))
        #expect(fixture.contents() == before, "the widget removed the purged account's unreadable glance")

        try VaultKeyring(store: fixture.appKeys).shred(account: live.rawValue)
        #expect(await GlanceReader(storeRoot: fixture.root, keyStore: fixture.widgetKeys).read() == .noGlance)
    }

    @Test("with two readable accounts, the newer glance wins")
    func newerGlanceWins() async throws {
        let fixture = GlanceStoreFixture()
        defer { fixture.remove() }
        try await fixture.commit(GlanceStoreFixture.account("older"), fetchedAt: Date(timeIntervalSince1970: 1_790_600_400))
        let newer = try await fixture.commit(GlanceStoreFixture.account("newer"), fetchedAt: Date(timeIntervalSince1970: 1_790_700_000))

        #expect(await GlanceReader(storeRoot: fixture.root, keyStore: fixture.widgetKeys).read() == .loaded(newer))
    }

    @Test("the widget's sealer cannot seal: it never creates a key or writes a file")
    func widgetSealerCannotSeal() {
        let sealer = VaultSealer(account: "a", keyring: VaultKeyring(store: InMemoryVaultKeyStore()), mayCreateKeys: false)
        #expect(throws: VaultError.readOnlyProcess) { try sealer.seal(Data("x".utf8), file: .glance) }
    }

    @Test("the widget's Info.plist values: a Team ID prefix is used, anything else counts as none")
    func configurationFromInfoPlist() {
        let base: [String: Any] = [GlanceConfiguration.appGroupIDKey: "group.dev.tally-app.tally",
                                   GlanceConfiguration.appBundleIDKey: "dev.tally-app.tally"]
        func group(_ prefix: Any?) -> String? {
            var info = base
            info[GlanceConfiguration.keychainAccessGroupPrefixKey] = prefix
            return GlanceConfiguration.from(infoDictionary: info)?.keychainAccessGroup
        }
        #expect(group("ABCDE12345.") == "ABCDE12345.group.dev.tally-app.tally")
        #expect(group("") == "group.dev.tally-app.tally")
        #expect(group(nil) == "group.dev.tally-app.tally")
        #expect(group("$(AppIdentifierPrefix)") == "group.dev.tally-app.tally")
        #expect(group("abcde12345.") == "group.dev.tally-app.tally")
        #expect(GlanceConfiguration.from(infoDictionary: [GlanceConfiguration.appGroupIDKey: "g"]) == nil)
        #expect(GlanceConfiguration.from(infoDictionary: nil) == nil)
        #expect(GlanceConfiguration.from(infoDictionary: base)?.appBundleID == "dev.tally-app.tally")
    }

    @Test("the store root is Library/Application Support/Tally inside the container (architecture.md §3.2)")
    func storeRoot() {
        let root = GlanceStoreLocation.storeRoot(inContainer: URL(fileURLWithPath: "/container", isDirectory: true))
        #expect(root.path == "/container/Library/Application Support/Tally")
    }
}

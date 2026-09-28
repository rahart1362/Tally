import CryptoKit
import Foundation
import Security
import Testing
import TallyDomain
import TallyPlatform
import TallyStore
import TallyTestSupport
@testable import TallyGlance

/// Plan 06 step 11 against the real Keychain (simulator): the widget's read-only key reader and
/// the app's `KeychainVaultKeyStore` agree on the key's name; the reader never answers for the app
/// audience and never writes; and without a Team ID (GO-LIVE GL-02) the production access group
/// degrades to the placeholder instead of failing. `.serialized`, like the other Keychain suites
/// (CI run 36338337384). Every test uses its own service prefix, so runs never collide.
@Suite("Widget glance: Keychain", .serialized)
struct WidgetGlanceKeychainTests {
    private static func uniqueBundleID() -> String { "dev.tally-app.tally.tests.widget.\(UUID().uuidString)" }

    /// The app's side: an owner store whose keys are real Keychain items, in the process's default
    /// access group (explicit groups need a Team ID on this runner, GL-02).
    private static func commit(_ account: AccountKey, root: URL, appStore: KeychainVaultKeyStore,
                               includeGrades: Bool = false) async throws -> GlanceProjection {
        let owner = SnapshotStore(root: root, accountKey: account,
                                  sealer: VaultSealer(account: account.rawValue, keyring: VaultKeyring(store: appStore),
                                                      mayCreateKeys: true))
        return try await owner.commit(CanvasSnapshotFixture.make(accountKey: account), includeGrades: includeGrades)
    }

    @Test("the widget's reader finds the key the app's KeychainVaultKeyStore wrote, and reads the glance")
    func readerFindsTheAppsKey() async throws {
        let bundleID = Self.uniqueBundleID()
        let appStore = KeychainVaultKeyStore(bundleID: bundleID)
        let fixture = GlanceStoreFixture()
        defer { fixture.remove(); try? appStore.deleteEverything() }
        let account = GlanceStoreFixture.account("keychain")
        let committed = try await Self.commit(account, root: fixture.root, appStore: appStore)

        let reader = WidgetVaultKeyReader(appBundleID: bundleID, accessGroup: nil)
        let result = await GlanceReader(storeRoot: fixture.root, keyStore: reader).read()

        #expect(result == .loaded(committed))
        let scope = KeyScope(account: account.rawValue, audience: .widget)
        #expect(try reader.keyIDs(for: scope) == appStore.keyIDs(for: scope))
    }

    @Test("the reader never answers for the app audience, so the widget cannot open the snapshot")
    func readerNeverAnswersForTheAppAudience() async throws {
        let bundleID = Self.uniqueBundleID()
        let appStore = KeychainVaultKeyStore(bundleID: bundleID)
        let fixture = GlanceStoreFixture()
        defer { fixture.remove(); try? appStore.deleteEverything() }
        let account = GlanceStoreFixture.account("keychain")
        _ = try await Self.commit(account, root: fixture.root, appStore: appStore)
        let appScope = KeyScope(account: account.rawValue, audience: .app)
        let appKeyIDs = try appStore.keyIDs(for: appScope)
        #expect(appKeyIDs.count == 1, "the app's commit did not create its app-audience key")

        let reader = WidgetVaultKeyReader(appBundleID: bundleID, accessGroup: nil)
        #expect(try reader.keyIDs(for: appScope) == [])
        #expect(try appKeyIDs.allSatisfy { try reader.key(id: $0, for: appScope) == nil })
        let widgetStore = SnapshotStore(
            root: fixture.root, accountKey: account,
            sealer: VaultSealer(account: account.rawValue, keyring: VaultKeyring(store: reader), mayCreateKeys: false),
            isOwner: false)
        #expect(await widgetStore.loadSnapshot() == .unavailable(.discardAndRebuild))
    }

    @Test("the reader never writes the Keychain: every write throws readOnlyProcess and the key stays")
    func readerNeverWrites() async throws {
        let bundleID = Self.uniqueBundleID()
        let appStore = KeychainVaultKeyStore(bundleID: bundleID)
        let fixture = GlanceStoreFixture()
        defer { fixture.remove(); try? appStore.deleteEverything() }
        let account = GlanceStoreFixture.account("keychain")
        _ = try await Self.commit(account, root: fixture.root, appStore: appStore)
        let scope = KeyScope(account: account.rawValue, audience: .widget)
        let before = try appStore.keyIDs(for: scope)

        let reader = WidgetVaultKeyReader(appBundleID: bundleID, accessGroup: nil)
        #expect(throws: VaultError.readOnlyProcess) { try reader.add(SymmetricKey(size: .bits256), id: 99, for: scope) }
        #expect(throws: VaultError.readOnlyProcess) { try reader.deleteAll(for: scope) }
        #expect(throws: VaultError.readOnlyProcess) { try reader.deleteEverything() }
        #expect(try appStore.keyIDs(for: scope) == before)
    }

    /// The production access group is the App Group ID behind the Team ID prefix. With no Team ID
    /// (GL-02) this runner's ad-hoc identity is not entitled to it (`errSecMissingEntitlement`,
    /// -34018, as `KeychainVaultKeyStoreTests` found for any explicit group), and the widget must
    /// show its placeholder, not fail. On a signed build the group is valid and holds no key from
    /// this test (the app side wrote to the default group), so the read finds no glance.
    @Test("the production access group without a Team ID degrades to the placeholder (-34018), never a failure")
    func productionGroupDegrades() async throws {
        let bundleID = Self.uniqueBundleID()
        let appStore = KeychainVaultKeyStore(bundleID: bundleID)
        let fixture = GlanceStoreFixture()
        defer { fixture.remove(); try? appStore.deleteEverything() }
        let account = GlanceStoreFixture.account("keychain")
        _ = try await Self.commit(account, root: fixture.root, appStore: appStore)
        let configuration = try #require(Self.embeddedWidgetConfiguration())

        let reader = WidgetVaultKeyReader(appBundleID: bundleID, accessGroup: configuration.keychainAccessGroup)
        let result = await GlanceReader(storeRoot: fixture.root, keyStore: reader).read()

        do {
            _ = try reader.keyIDs(for: KeyScope(account: account.rawValue, audience: .widget))
            #expect(result == .noGlance)
        } catch {
            #expect(error as? VaultError == .storage(code: Int(errSecMissingEntitlement)))
            #expect(result == .unavailable)
            let plan = GlanceTimelinePlanner.plan(for: result, now: Date(), calendar: .current)
            #expect(plan.current.content == .message(.unavailable))
        }
    }

    /// The production path end to end: the app writes the widget key into the App Group access
    /// group and the widget reads it through the same group. The platform forces the known issue:
    /// without a Team ID (GO-LIVE GL-02) this runner cannot use any explicit access group (-34018).
    /// When GL-02 lands, the known issue stops occurring and Swift Testing fails this test, which
    /// is the signal to remove `withKnownIssue`.
    @Test("with a Team ID, the glance round-trips through the App Group access group (known issue until GL-02)")
    func appGroupRoundTrip() async throws {
        let configuration = try #require(Self.embeddedWidgetConfiguration())
        let bundleID = Self.uniqueBundleID()
        let appStore = KeychainVaultKeyStore(bundleID: bundleID, widgetAccessGroup: configuration.keychainAccessGroup)
        let fixture = GlanceStoreFixture()
        defer { fixture.remove(); try? appStore.deleteEverything() }
        await withKnownIssue("""
            SecItemAdd/SecItemCopyMatching with an explicit kSecAttrAccessGroup fail with \
            errSecMissingEntitlement (-34018) under this runner's ad-hoc signing, which has no Team \
            ID. Needs a real Team ID (GO-LIVE GL-02) or a device.
            """) {
            let account = GlanceStoreFixture.account("app-group")
            let committed = try await Self.commit(account, root: fixture.root, appStore: appStore)
            let reader = WidgetVaultKeyReader(appBundleID: bundleID, accessGroup: configuration.keychainAccessGroup)
            #expect(await GlanceReader(storeRoot: fixture.root, keyStore: reader).read() == .loaded(committed))
        }
    }

    @Test("the embedded widget's Info.plist carries the app's bundle ID and App Group, and both manifests ship")
    func embeddedWidgetIsConfigured() throws {
        let appex = try #require(Self.embeddedWidgetBundle(), "no TallyWidgets.appex in \(Bundle.main.bundlePath)")
        let info = try #require(appex.infoDictionary)
        let configuration = try #require(GlanceConfiguration.from(infoDictionary: info))

        #expect(configuration.appBundleID == Bundle.main.bundleIdentifier)
        #expect(configuration.appGroupID == Bundle.main.object(forInfoDictionaryKey: "TallyAppGroupID") as? String)
        #expect(configuration.keychainAccessGroup.hasSuffix(configuration.appGroupID))
        // `$(AppIdentifierPrefix)` expands to "TEAMID." with a team and to nothing without one;
        // never a literal the build left unexpanded.
        let prefix = info[GlanceConfiguration.keychainAccessGroupPrefixKey] as? String
        #expect(prefix?.isEmpty == true || GlanceConfiguration.isTeamIDPrefix(prefix ?? ""),
                "TallyKeychainAccessGroupPrefix is \(String(describing: prefix))")
        let extensionInfo = info["NSExtension"] as? [String: Any]
        #expect(extensionInfo?["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension")
        // ASC-03: each bundle carries its own privacy manifest (app-store-compliance.md R2).
        #expect(appex.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") != nil)
        #expect(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") != nil)
    }

    private static func embeddedWidgetBundle() -> Bundle? {
        Bundle.main.builtInPlugInsURL.flatMap { Bundle(url: $0.appendingPathComponent("TallyWidgets.appex")) }
    }

    private static func embeddedWidgetConfiguration() -> GlanceConfiguration? {
        GlanceConfiguration.from(infoDictionary: embeddedWidgetBundle()?.infoDictionary)
    }
}

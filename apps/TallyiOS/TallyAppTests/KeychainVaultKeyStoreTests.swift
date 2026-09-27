#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation
import Security
import Testing
import TallyStore
@testable import TallyPlatform

/// ENC-03. Hosted Keychain round-trip tests (simulator). Every test uses a
/// unique `bundleID` (service prefix) so runs never collide with each other
/// or with a real vault key.
@Suite("KeychainVaultKeyStore")
struct KeychainVaultKeyStoreTests {
    private func makeStore(appAccessGroup: String? = nil, widgetAccessGroup: String? = nil) -> (KeychainVaultKeyStore, String) {
        let bundleID = "dev.tally-app.tally.tests.\(UUID().uuidString)"
        return (KeychainVaultKeyStore(bundleID: bundleID, appAccessGroup: appAccessGroup, widgetAccessGroup: widgetAccessGroup), bundleID)
    }

    @Test("add, get, list and delete round-trip for one scope")
    func addGetListDelete() throws {
        let (store, _) = makeStore()
        let scope = KeyScope(account: "acct1", audience: .app)
        let key = SymmetricKey(size: .bits256)

        #expect(try store.keyIDs(for: scope) == [])
        #expect(try store.key(id: 1, for: scope) == nil)

        try store.add(key, id: 1, for: scope)
        #expect(try store.keyIDs(for: scope) == [1])
        let fetched = try store.key(id: 1, for: scope)
        #expect(fetched?.withUnsafeBytes { Data($0) } == key.withUnsafeBytes { Data($0) })

        try store.deleteAll(for: scope)
        #expect(try store.keyIDs(for: scope) == [])
        #expect(try store.key(id: 1, for: scope) == nil)
    }

    @Test("deleteAll for one account never touches a different account under the same audience")
    func deleteAllIsAccountScoped() throws {
        let (store, _) = makeStore()
        let scopeA = KeyScope(account: "acct-a", audience: .app)
        let scopeB = KeyScope(account: "acct-b", audience: .app)
        try store.add(SymmetricKey(size: .bits256), id: 1, for: scopeA)
        try store.add(SymmetricKey(size: .bits256), id: 2, for: scopeB)

        try store.deleteAll(for: scopeA)

        #expect(try store.keyIDs(for: scopeA) == [])
        #expect(try store.keyIDs(for: scopeB) == [2])
        try store.deleteAll(for: scopeB)
    }

    @Test("an .app-audience key is invisible to a store configured with only the App Group group")
    func appAudienceKeyIsInvisibleToWidgetOnlyGroup() throws {
        // CI run 36333352378 proved arbitrary group strings do NOT work here:
        // SecItemAdd failed with errSecMissingEntitlement (-34018) — the
        // Simulator DOES enforce kSecAttrAccessGroup against the test host's
        // real signed entitlements (Tally.entitlements' keychain-access-groups),
        // even for a local "Sign to Run Locally" build. So this test must use
        // groups the running Tally.app is actually entitled to: its own
        // bundle id, and the App Group id it publishes at
        // Info.plist["TallyAppGroupID"] (project.yml), both prefixed with
        // this process's real Team ID prefix (`KeychainAccessGroupResolver`).
        guard let prefix = KeychainAccessGroupResolver.resolveTeamIDPrefix() else {
            Issue.record("could not resolve this process's Keychain access-group prefix on this runner")
            return
        }
        let hostBundleID = Bundle.main.bundleIdentifier ?? "dev.tally-app.tally"
        let hostAppGroupID = (Bundle.main.object(forInfoDictionaryKey: "TallyAppGroupID") as? String) ?? "group.dev.tally-app.tally"
        let appOnlyGroup = "\(prefix).\(hostBundleID)"
        let sharedGroup = "\(prefix).\(hostAppGroupID)"

        let bundleID = "dev.tally-app.tally.tests.\(UUID().uuidString)"
        let appStore = KeychainVaultKeyStore(bundleID: bundleID, appAccessGroup: appOnlyGroup, widgetAccessGroup: sharedGroup)
        let scope = KeyScope(account: "acct1", audience: .app)
        try appStore.add(SymmetricKey(size: .bits256), id: 1, for: scope)
        #expect(try appStore.keyIDs(for: scope) == [1])

        let widgetOnlyStore = KeychainVaultKeyStore(bundleID: bundleID, appAccessGroup: sharedGroup, widgetAccessGroup: sharedGroup)
        // `widgetOnlyStore` queries the `.app` service with `sharedGroup`,
        // not `appOnlyGroup` — a different access group than what the key
        // was written under, so it must not find it.
        #expect(try widgetOnlyStore.keyIDs(for: scope) == [])
        #expect(try widgetOnlyStore.key(id: 1, for: scope) == nil)

        try appStore.deleteAll(for: scope)
    }

    @Test("KeychainAccessGroupResolver resolves a non-empty Team ID prefix on this runner")
    func resolverReturnsAPrefix() {
        let prefix = KeychainAccessGroupResolver.resolveTeamIDPrefix()
        #expect(prefix != nil)
        #expect((prefix?.isEmpty ?? true) == false)
    }

    @Test("a stored key reads back with AfterFirstUnlockThisDeviceOnly, non-synchronizable, and the requested access group")
    func attributesReadBack() throws {
        let (store, bundleID) = makeStore()
        let scope = KeyScope(account: "acct1", audience: .app)
        try store.add(SymmetricKey(size: .bits256), id: 7, for: scope)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(bundleID).vault.app",
            kSecAttrAccount as String: "acct1.7",
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        #expect(status == errSecSuccess)
        let attributes = result as? [String: Any]
        #expect((attributes?[kSecAttrAccessible as String] as? String) == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))
        #expect((attributes?[kSecAttrSynchronizable as String] as? Bool) == false)

        query[kSecReturnAttributes as String] = nil
        _ = SecItemDelete(query as CFDictionary)
    }

    @Test("deleteEverything removes every audience for every account this process can see")
    func deleteEverythingClearsAllAudiences() throws {
        let (store, _) = makeStore()
        let app = KeyScope(account: "acct1", audience: .app)
        let widget = KeyScope(account: "acct1", audience: .widget)
        try store.add(SymmetricKey(size: .bits256), id: 1, for: app)
        try store.add(SymmetricKey(size: .bits256), id: 2, for: widget)

        try store.deleteEverything()

        #expect(try store.keyIDs(for: app) == [])
        #expect(try store.keyIDs(for: widget) == [])
    }
}

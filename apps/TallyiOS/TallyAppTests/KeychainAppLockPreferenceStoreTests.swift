import Foundation
import Security
import Testing
import TallyFeatures
@testable import TallyPlatform

/// SEC-07: the app-lock setting in the Keychain (ADR 0001), hosted on the simulator. Each test uses
/// its own service, and the suite is `.serialized` for the same securityd reason as
/// `KeychainCredentialStoreTests`.
@Suite("KeychainAppLockPreferenceStore", .serialized)
struct KeychainAppLockPreferenceStoreTests {
    private func makeStore() -> (KeychainAppLockPreferenceStore, String) {
        let service = "dev.tally-app.tally.tests.app-lock.\(UUID().uuidString)"
        return (KeychainAppLockPreferenceStore(service: service), service)
    }

    @Test("nothing stored: notFound (the lock is off); save, load, update and reset round-trip")
    func roundTrip() async throws {
        let (store, _) = makeStore()
        #expect(await store.load() == .notFound)
        #expect(await store.load().effective == .disabled)

        try await store.save(AppLockPreference(isEnabled: true, gracePeriod: .fiveMinutes))
        #expect(await store.load() == .found(AppLockPreference(isEnabled: true, gracePeriod: .fiveMinutes)))
        try await store.save(AppLockPreference(isEnabled: false, gracePeriod: .immediately))
        #expect(await store.load() == .found(AppLockPreference(isEnabled: false, gracePeriod: .immediately)))

        await store.reset()
        #expect(await store.load() == .notFound)
        await store.reset() // idempotent
    }

    @Test("one item, AfterFirstUnlockThisDeviceOnly, never synchronizable, updated in place")
    func itemAttributes() async throws {
        let (store, service) = makeStore()
        try await store.save(AppLockPreference(isEnabled: true))
        try await store.save(AppLockPreference(isEnabled: true, gracePeriod: .fifteenMinutes))

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        #expect(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
        let items = (result as? [[String: Any]]) ?? []
        #expect(items.count == 1, "the update added a second item")
        #expect((items.first?[kSecAttrAccessible as String] as? String)
                == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String))
        #expect((items.first?[kSecAttrSynchronizable as String] as? Bool) != true)
        await store.reset()
    }
}

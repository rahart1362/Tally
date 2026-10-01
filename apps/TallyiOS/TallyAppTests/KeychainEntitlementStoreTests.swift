import Foundation
import Security
import Testing
import TallyDomain
import TallyFeatures
@testable import TallyPlatform

/// PAY-04 (M3-B1): the entitlement record in the Keychain, hosted on the simulator. Each test uses
/// its own service, and the suite is `.serialized` for the same securityd reason as
/// `KeychainAppLockPreferenceStoreTests`.
@Suite("KeychainEntitlementStore (PAY-04)", .serialized)
struct KeychainEntitlementStoreTests {
    private func makeStore() -> (KeychainEntitlementStore, String) {
        let service = "dev.tally-app.tally.tests.entitlement.\(UUID().uuidString)"
        return (KeychainEntitlementStore(service: service), service)
    }

    @Test("Nothing stored: notFound; save, load, update and reset round-trip, dates exactly")
    func roundTrip() async throws {
        let (store, _) = makeStore()
        #expect(await store.load() == .notFound)

        let until = Date(timeIntervalSince1970: 1_820_000_000.123456)
        let record = EntitlementRecord(studentUntil: until, verifiedAt: Date(timeIntervalSince1970: 1_790_000_000.654321))
        try await store.save(record)
        #expect(await store.load() == .found(record), "the expiry and the verification time, to the bit")

        let lapsed = record.recording(.lapsed(since: until), for: .student, verifiedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try await store.save(lapsed)
        #expect(await store.load() == .found(lapsed))
        #expect(await store.load().record?.studentUntil == nil)

        await store.reset()
        #expect(await store.load() == .notFound)
        await store.reset() // idempotent
    }

    @Test("One item, AfterFirstUnlockThisDeviceOnly, never synchronizable, updated in place")
    func itemAttributes() async throws {
        let (store, service) = makeStore()
        try await store.save(EntitlementRecord(studentUntil: Date(timeIntervalSince1970: 1_820_000_000), verifiedAt: Date()))
        try await store.save(EntitlementRecord(parentUntil: Date(timeIntervalSince1970: 1_830_000_000), verifiedAt: Date()))

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

    @Test("An undecodable item is unavailable, not absent: access fails closed until StoreKit answers")
    func undecodableIsUnavailable() async throws {
        let (store, service) = makeStore()
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "record",
            kSecValueData as String: Data("not a record".utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true,
        ]
        #expect(SecItemAdd(add as CFDictionary, nil) == errSecSuccess)
        #expect(await store.load() == .unavailable)
        await store.reset()
    }

    /// PAY-07's "no background task scheduled", against the live `BGTaskScheduler` adapter. The
    /// simulator never runs background tasks (`submit` fails there), so the meaningful lapse check is
    /// `SubscriptionEngineTests.lapseEndToEnd` over a recording scheduler; this one shows the live
    /// adapter's cancel leaves nothing pending and neither call traps.
    @Test("The live background scheduler: after a cancel, nothing is pending")
    func liveBackgroundScheduler() async {
        let scheduler = BackgroundRefreshScheduler()
        await scheduler.schedule(earliestBegin: Date().addingTimeInterval(3_600))
        await scheduler.cancel()
        #expect(await scheduler.isScheduled() == false)
    }
}

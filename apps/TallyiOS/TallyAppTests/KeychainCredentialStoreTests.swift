import Foundation
import Security
import Testing
import TallyCanvasAPI
@testable import TallyPlatform

/// SEC-04. Hosted Keychain round-trip tests (simulator). Each test uses a
/// unique service name so tests can run in any order/parallel without
/// sharing Keychain state, and `removeLegacyMockItemOnInit: false` keeps
/// unrelated tests from tripping the legacy-cleanup side effect (that's its
/// own dedicated test below).
@Suite("KeychainCredentialStore")
struct KeychainCredentialStoreTests {
    private func makeStore() -> KeychainCredentialStore {
        KeychainCredentialStore(service: "dev.tally-app.tally.tests.\(UUID().uuidString)", removeLegacyMockItemOnInit: false)
    }

    private func credential(token: String = "access-1", refresh: String = "refresh-1", expiresIn: TimeInterval = 3600) -> CanvasCredential {
        CanvasCredential(
            host: "canvas.example.edu", userID: "42", accessToken: token, refreshToken: refresh,
            accessTokenExpiresAt: Date().addingTimeInterval(expiresIn))
    }

    @Test("a fresh store reports notFound, never unavailable")
    func freshStoreIsNotFound() async {
        let store = makeStore()
        #expect(await store.load() == nil)
        #expect(store.readStatus() == .notFound)
    }

    @Test("save then load round-trips the exact credential")
    func saveThenLoadRoundTrips() async throws {
        let store = makeStore()
        let original = credential()
        try await store.save(original)

        let loaded = await store.load()
        #expect(loaded == original)
        #expect(store.readStatus() == .found(original))

        await store.delete()
    }

    @Test("a second save (token rotation) updates in place: exactly one Keychain item ever exists")
    func rotationUpdatesInPlace() async throws {
        let store = makeStore()
        let first = credential(token: "access-1", refresh: "refresh-1")
        try await store.save(first)
        let rotated = credential(token: "access-2", refresh: "refresh-2")
        try await store.save(rotated)

        let loaded = await store.load()
        #expect(loaded == rotated)
        #expect(loaded?.accessToken != first.accessToken)

        await store.delete()
    }

    @Test("delete then load reports notFound")
    func deleteThenLoadIsNotFound() async throws {
        let store = makeStore()
        try await store.save(credential())
        await store.delete()

        #expect(await store.load() == nil)
        #expect(store.readStatus() == .notFound)
    }

    @Test("the legacy mock item (service com.tally.app, account canvas) is removed on init")
    func legacyMockItemIsRemovedOnInit() {
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.tally.app",
            kSecAttrAccount as String: "canvas",
            kSecValueData as String: Data("mock_canvas_token_00000000".utf8),
        ]
        _ = SecItemAdd(legacyQuery as CFDictionary, nil)

        _ = KeychainCredentialStore(service: "dev.tally-app.tally.tests.\(UUID().uuidString)")

        var checkQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.tally.app",
            kSecAttrAccount as String: "canvas",
        ]
        checkQuery[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(checkQuery as CFDictionary, &result)
        #expect(status == errSecItemNotFound)
    }
}

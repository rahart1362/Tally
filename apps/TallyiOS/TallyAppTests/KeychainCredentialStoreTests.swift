import Foundation
import Security
import Testing
import TallyCanvasAPI
@testable import TallyPlatform

/// SEC-04. Hosted Keychain round-trip tests (simulator). Each test uses a
/// unique service name so tests can never share Keychain state with each
/// other, but the suite is `.serialized`: CI run 36338337384 saw
/// `rotationUpdatesInPlace` fail once (`loaded == rotated`) despite passing
/// cleanly with byte-identical code the run before, with no code change to
/// this file in between -- the implementation brief's own guidance is "if a
/// test involves timing or concurrency, run it 3 times", and by default
/// Swift Testing runs every `@Test` in every suite concurrently, so dozens
/// of Add/Update/CopyMatching calls from unrelated suites can hit the same
/// simulator's securityd at once. Serializing removes that as a variable;
/// `rotationUpdatesInPlace` below also now repeats the rotate-and-verify
/// cycle 3 times and checks the raw item count after each round.
@Suite("KeychainCredentialStore", .serialized)
struct KeychainCredentialStoreTests {
    private func makeStore() -> KeychainCredentialStore {
        KeychainCredentialStore(service: "dev.tally-app.tally.tests.\(UUID().uuidString)", removeLegacyMockItemOnInit: false)
    }

    private func credential(token: String = "access-1", refresh: String = "refresh-1", expiresIn: TimeInterval = 3600) -> CanvasCredential {
        CanvasCredential(
            host: "canvas.example.edu", userID: "42", accessToken: token, refreshToken: refresh,
            accessTokenExpiresAt: Date().addingTimeInterval(expiresIn))
    }

    /// Raw item count for a service, bypassing `KeychainCredentialStore`
    /// entirely, so a test can independently confirm "exactly one item"
    /// rather than trusting the adapter's own read path.
    private func itemCount(service: String) -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return 0 }
        guard status == errSecSuccess else { return -1 }
        return (result as? [[String: Any]])?.count ?? ((result != nil) ? 1 : 0)
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
        let service = "dev.tally-app.tally.tests.\(UUID().uuidString)"
        let store = KeychainCredentialStore(service: service, removeLegacyMockItemOnInit: false)

        // Timing/concurrency-sensitive (per the implementation brief): 3 rounds.
        for round in 1...3 {
            let first = credential(token: "access-\(round)-1", refresh: "refresh-\(round)-1")
            try await store.save(first)
            #expect(itemCount(service: service) == 1, "round \(round), after first save")

            let rotated = credential(token: "access-\(round)-2", refresh: "refresh-\(round)-2")
            try await store.save(rotated)
            #expect(itemCount(service: service) == 1, "round \(round), after rotation (never delete-then-add)")

            let loaded = await store.load()
            #expect(loaded == rotated, "round \(round)")
            #expect(loaded?.accessToken != first.accessToken, "round \(round)")
        }

        await store.delete()
        #expect(itemCount(service: service) == 0)
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

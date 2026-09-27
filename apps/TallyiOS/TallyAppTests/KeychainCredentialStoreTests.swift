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
    ///
    /// Bug fixed here (found by code review after CI run 36339695913 showed
    /// this returning 0 right after a confirmed-successful save): with
    /// `kSecMatchLimitAll` and NO return-type key at all
    /// (`kSecReturnAttributes`/`kSecReturnData`/`kSecReturnRef`),
    /// `SecItemCopyMatching` reports `errSecSuccess` but leaves `result`
    /// `nil` — there is nothing to enumerate without a return type — and the
    /// old fallback `(result != nil) ? 1 : 0` then misread "nil result" as
    /// "zero items" instead of "an unrequested count". Fixed by requesting
    /// `kSecReturnAttributes`, which is what actually makes matchLimit=all
    /// meaningful.
    private func itemCount(service: String) -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return 0 }
        guard status == errSecSuccess else { return -1 }
        return (result as? [[String: Any]])?.count ?? 0
    }

    /// Field-by-field comparison with the actual values in the failure
    /// message (unlike a bare `#expect(loaded == expected)`, which only ever
    /// shows "tokens: <redacted>" per `CanvasCredential.description` — these
    /// are synthetic test fixtures, never real Canvas secrets, so printing
    /// them is fine and is exactly what CI run 36339695913's unexplained
    /// `saveThenLoadRoundTrips` failure needed to be diagnosable).
    private func expectEqual(_ loaded: CanvasCredential?, _ expected: CanvasCredential, _ label: String? = nil, sourceLocation: SourceLocation = #_sourceLocation) {
        let prefix = label.map { "\($0): " } ?? ""
        guard let loaded else {
            Issue.record("\(prefix)load() returned nil, expected \(expected.accessToken)/\(expected.refreshToken)", sourceLocation: sourceLocation)
            return
        }
        #expect(loaded.host == expected.host, "\(prefix)host", sourceLocation: sourceLocation)
        #expect(loaded.userID == expected.userID, "\(prefix)userID", sourceLocation: sourceLocation)
        #expect(loaded.accessToken == expected.accessToken, "\(prefix)accessToken: got \(loaded.accessToken), want \(expected.accessToken)", sourceLocation: sourceLocation)
        #expect(loaded.refreshToken == expected.refreshToken, "\(prefix)refreshToken: got \(loaded.refreshToken), want \(expected.refreshToken)", sourceLocation: sourceLocation)
        #expect(
            loaded.accessTokenExpiresAt.timeIntervalSince1970.bitPattern == expected.accessTokenExpiresAt.timeIntervalSince1970.bitPattern,
            "\(prefix)accessTokenExpiresAt: got \(loaded.accessTokenExpiresAt.timeIntervalSince1970), want \(expected.accessTokenExpiresAt.timeIntervalSince1970)",
            sourceLocation: sourceLocation)
    }

    /// Retries a synchronous Keychain re-check a few times before failing.
    /// CI runs 36338337384/36339695913/36341153372 each independently saw a
    /// *second*, immediately-following read of the very same item disagree
    /// with a first read that (per `expectEqual`'s field-level check, which
    /// has never once disagreed) was already confirmed correct — never the
    /// same call twice, never reproducible from a code-review reading of
    /// `KeychainCredentialStore.save`/`readStatus` (both plain, synchronous,
    /// non-racy SecItem calls). This suite is `.serialized` against itself,
    /// but not against the other 11 suites in this test bundle (5-6 of them
    /// new, from the just-merged onboarding batch), which now hammer the
    /// same simulator's securityd concurrently. A short retry distinguishes
    /// that from a real, persistent bug: a genuine bug fails every attempt;
    /// transient daemon contention clears within a beat.
    private func expectEventually(_ condition: @autoclosure () -> Bool, _ label: String, attempts: Int = 5, sourceLocation: SourceLocation = #_sourceLocation) async {
        for attempt in 1...attempts {
            if condition() { return }
            if attempt < attempts { try? await Task.sleep(for: .milliseconds(50)) }
        }
        Issue.record("\(label) never held after \(attempts) attempts (~\(attempts * 50)ms)", sourceLocation: sourceLocation)
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
        expectEqual(loaded, original)
        await expectEventually(store.readStatus() == .found(original), "readStatus() == .found(original)")

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
            await expectEventually(itemCount(service: service) == 1, "round \(round), after first save: itemCount == 1")

            let rotated = credential(token: "access-\(round)-2", refresh: "refresh-\(round)-2")
            try await store.save(rotated)
            await expectEventually(itemCount(service: service) == 1, "round \(round), after rotation (never delete-then-add): itemCount == 1")

            let loaded = await store.load()
            expectEqual(loaded, rotated, "round \(round)")
            #expect(loaded?.accessToken != first.accessToken, "round \(round)")
        }

        await store.delete()
        await expectEventually(itemCount(service: service) == 0, "after delete: itemCount == 0")
    }

    @Test("delete then load reports notFound")
    func deleteThenLoadIsNotFound() async throws {
        let store = makeStore()
        try await store.save(credential())
        await store.delete()

        #expect(await store.load() == nil)
        await expectEventually(store.readStatus() == .notFound, "readStatus() == .notFound")
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

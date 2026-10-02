import Foundation
import Synchronization
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyCanvasAPI

/// PAY-10 (M3-B2): when a school turns off Tally's developer key, Canvas answers the token refresh
/// with `invalid_client` (RFC 6749 §5.2). The auth state machine reports `.schoolDisabled`, not a
/// sign-in to repeat: the tokens and the saved data stay, and every refresh until the school turns
/// the key back on says so (the app's school-revoked notice reads `RefreshFailure.schoolDisabled`).
@Suite("PAY-10: invalid_client means the school turned Tally off")
struct SchoolDisabledTests {
    private let host = "canvas.northfield.example"
    private let clock = TestClock()

    /// A refresh-token grant that always fails with `failure`, counting its calls.
    private final class FailingRefresher: TokenRefreshing {
        private let calls = Mutex(0)
        let failure: any Error & Sendable
        init(_ failure: any Error & Sendable) { self.failure = failure }
        var callCount: Int { calls.withLock { $0 } }

        func refresh(_ credential: CanvasCredential) async throws -> CanvasCredential {
            calls.withLock { $0 += 1 }
            throw failure
        }
    }

    private func credential(expiresIn seconds: TimeInterval) -> CanvasCredential {
        CanvasCredential(host: host, userID: "4820117", accessToken: "token-1", refreshToken: "refresh-1",
                         accessTokenExpiresAt: clock.now().addingTimeInterval(seconds))
    }

    @Test("The token endpoint maps invalid_client to .invalidClient, and still maps invalid_grant to .invalidGrant")
    func endpointMapsInvalidClient() {
        let endpoint = TokenEndpoint(host: host, clientID: "10000000000042")
        let previous = credential(expiresIn: 0)
        #expect(throws: TokenEndpointError.invalidClient) {
            try endpoint.credential(from: HTTPResponse(status: 401, body: Data(#"{"error":"invalid_client","error_description":"unknown client"}"#.utf8)),
                                    previous: previous, now: clock.now())
        }
        #expect(throws: TokenEndpointError.invalidGrant) {
            try endpoint.credential(from: HTTPResponse(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8)),
                                    previous: previous, now: clock.now())
        }
        #expect(throws: TokenEndpointError.rejected(status: 401)) {
            try endpoint.credential(from: HTTPResponse(status: 401, body: Data(#"{"error":"unauthorized_client"}"#.utf8)),
                                    previous: previous, now: clock.now())
        }
    }

    @Test("The token coordinator reports .schoolDisabled, keeps the tokens and asks Canvas again next time")
    func coordinatorKeepsTokens() async throws {
        let store = InMemoryCredentialStore(credential(expiresIn: 30))
        let refresher = FailingRefresher(TokenEndpointError.invalidClient)
        let coordinator = TokenCoordinator(initial: credential(expiresIn: 30), store: store, refresher: refresher, clock: clock)
        await #expect(throws: AuthError.schoolDisabled) { try await coordinator.accessToken() }
        await #expect(throws: AuthError.schoolDisabled) { try await coordinator.accessToken() }
        #expect(refresher.callCount == 2, "the tokens were dropped, so the second refresh never asked Canvas")
        #expect(store.credential != nil && store.log.isEmpty, "the credential was deleted: \(store.log)")
        #expect(await coordinator.needsReauth == false)
    }

    @Test("A sign-in problem still drops the tokens (invalid_grant), unlike invalid_client")
    func invalidGrantStillDropsTokens() async throws {
        let store = InMemoryCredentialStore(credential(expiresIn: 30))
        let coordinator = TokenCoordinator(initial: credential(expiresIn: 30), store: store,
                                           refresher: FailingRefresher(TokenEndpointError.invalidGrant), clock: clock)
        await #expect(throws: AuthError.reauthRequired) { try await coordinator.accessToken() }
        #expect(store.credential == nil)
    }

    @Test("A Canvas request whose token refresh meets invalid_client fails with RefreshFailure.schoolDisabled")
    func clientMapsToSchoolDisabled() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let store = InMemoryCredentialStore(credential(expiresIn: 3600))
        let refresher = FailingRefresher(TokenEndpointError.invalidClient)
        let tokens = TokenCoordinator(initial: credential(expiresIn: 3600), store: store, refresher: refresher, clock: clock)
        let client = CanvasClient(host: host, transport: transport, tokens: tokens)
        await transport.inject(response: try ReplayTransport.errorResponse("401-invalid-access-token"), times: 1,
                               matching: { $0.url.path == "/api/v1/users/self/profile" })
        await #expect(throws: RefreshFailure.schoolDisabled) {
            _ = try await client.fetchOne(path: "/api/v1/users/self/profile")
        }
        #expect(refresher.callCount == 1)
        #expect(store.credential != nil, "the school's switch is not the student's sign-in: the tokens stay")
    }

    @Test("A refresh that failed with .schoolDisabled keeps the saved data on screen and persists as such")
    func freshnessKeepsSavedData() throws {
        let saved = clock.now()
        var record = RefreshRecord()
        record.began(.launch, at: saved)
        record.succeeded(dataFetchedAt: saved)
        record.began(.foreground, at: saved.addingTimeInterval(60))
        record.failed(.schoolDisabled)
        #expect(FreshnessRules.state(of: record, now: saved.addingTimeInterval(61)) == .failed(.schoolDisabled, showing: saved))
        let decoded = try JSONDecoder().decode(RefreshRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded.lastFailure == .schoolDisabled)
    }
}

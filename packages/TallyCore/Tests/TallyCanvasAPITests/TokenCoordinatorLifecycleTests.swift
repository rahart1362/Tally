import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyCanvasAPI

/// SH-4 (sync-hardening.md; crash-safety.md "Remaining risks"): nothing keeps a `TokenCoordinator`
/// alive once its owner lets go, after the paths it normally takes: a refresh shared by concurrent
/// callers (its single-flight `inFlight` task), a rejection answered with the already-refreshed
/// token, a rejection that refreshes again, and a refresh that fails for good and drops the tokens.
@Suite("TokenCoordinator lifecycle: deallocates after typical use (SH-4)")
struct TokenCoordinatorLifecycleTests {
    private let clock = TestClock()

    /// Rotates the token on every call ("a2", "a3", ...), or always throws `failure`.
    private actor RotatingRefresher: TokenRefreshing {
        private var calls = 0
        private let failure: TokenEndpointError?
        init(failure: TokenEndpointError? = nil) { self.failure = failure }

        func refresh(_ credential: CanvasCredential) async throws -> CanvasCredential {
            calls += 1
            let call = calls
            try await Task.sleep(for: .milliseconds(10)) // long enough for concurrent callers to join the one refresh
            if let failure { throw failure }
            var next = credential
            next.accessToken = "a\(call + 1)"
            next.refreshToken = "r\(call + 1)"
            next.accessTokenExpiresAt = Date(timeIntervalSince1970: 1_790_604_000) // the fixtures' anchor + 1 h
            return next
        }
    }

    private func credential(expiresIn seconds: TimeInterval) -> CanvasCredential {
        CanvasCredential(host: "canvas.northfield.example", userID: "42", accessToken: "a1", refreshToken: "r1",
                         accessTokenExpiresAt: clock.now().addingTimeInterval(seconds))
    }

    @Test func deallocatesAfterTypicalUse() async throws {
        weak var weakTokens: TokenCoordinator?
        weak var weakDroppedTokens: TokenCoordinator?
        do {
            let tokens = TokenCoordinator(initial: credential(expiresIn: 30), store: InMemoryCredentialStore(),
                                          refresher: RotatingRefresher(), clock: clock)
            weakTokens = tokens
            let shared = try await withThrowingTaskGroup(of: String.self) { group in
                for _ in 0..<5 { group.addTask { try await tokens.accessToken() } }
                return try await group.reduce(into: Set<String>()) { $0.insert($1) }
            }
            #expect(shared == ["a2"], "one refresh, shared by every concurrent caller")
            clock.advance(by: .seconds(120)) // past `TokenCoordinator.refreshLoopGuard`
            #expect(try await tokens.tokenAfterRejection(of: "a1") == "a2", "a stale rejection reuses the new token")
            #expect(try await tokens.tokenAfterRejection(of: "a2") == "a3", "a fresh rejection refreshes again")

            let droppedTokens = TokenCoordinator(initial: credential(expiresIn: 30), store: InMemoryCredentialStore(),
                                                 refresher: RotatingRefresher(failure: .invalidGrant), clock: clock)
            weakDroppedTokens = droppedTokens
            await #expect(throws: AuthError.reauthRequired) { try await droppedTokens.accessToken() }
        }
        #expect(weakTokens == nil, "TokenCoordinator must not outlive its owner")
        #expect(weakDroppedTokens == nil, "nor after it has dropped its tokens")
    }
}

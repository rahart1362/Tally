import Foundation
import Synchronization
import Testing
import TallyTestSupport
@testable import TallyCanvasAPI

/// Scripted refresher: counts calls, can be slow, can fail.
private final class FakeRefresher: TokenRefreshing {
    private let calls = Mutex(0)
    let failure: (any Error)?
    let delay: Duration
    init(failure: (any Error)? = nil, delay: Duration = .milliseconds(30)) { self.failure = failure; self.delay = delay }
    var callCount: Int { calls.withLock { $0 } }

    func refresh(_ credential: CanvasCredential) async throws -> CanvasCredential {
        let n = calls.withLock { $0 += 1; return $0 }
        try await Task.sleep(for: delay)
        if let failure { throw failure }
        var next = credential
        next.accessToken = "a\(n + 1)"; next.refreshToken = "r\(n + 1)"
        next.accessTokenExpiresAt = Date(timeIntervalSince1970: 1_790_604_000) // anchor + 1 h
        return next
    }
}

@Suite("TokenCoordinator: single-flight refresh and 401 handling")
struct TokenCoordinatorTests {
    let clock = TestClock()

    private func credential(expiresIn seconds: TimeInterval) -> CanvasCredential {
        CanvasCredential(host: "canvas.northfield.example", userID: "42", accessToken: "a1", refreshToken: "r1",
                         accessTokenExpiresAt: clock.now().addingTimeInterval(seconds))
    }

    @Test func fiftyConcurrent401sRefreshOnceAndPersistFirst() async throws {
        let store = InMemoryCredentialStore(), refresher = FakeRefresher()
        let coordinator = TokenCoordinator(initial: credential(expiresIn: 3000), store: store, refresher: refresher, clock: clock)
        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    let token = try await coordinator.tokenAfterRejection(of: "a1")
                    store.note("resumed")
                    return token
                }
            }
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }
        #expect(refresher.callCount == 1)
        #expect(Set(tokens) == ["a2"] && tokens.count == 50)
        #expect(store.log.first == "saved:a2", "the rotated token is saved before any caller resumes")
        #expect(store.credential?.refreshToken == "r2")
    }

    @Test func usableTokenNeedsNoRefreshExpiredOneRefreshesOnce() async throws {
        let refresher = FakeRefresher()
        let fresh = TokenCoordinator(initial: credential(expiresIn: 3000), store: InMemoryCredentialStore(), refresher: refresher, clock: clock)
        #expect(try await fresh.accessToken() == "a1" && refresher.callCount == 0)
        let stale = TokenCoordinator(initial: credential(expiresIn: 30), store: InMemoryCredentialStore(), refresher: refresher, clock: clock)
        #expect(try await stale.accessToken() == "a2" && refresher.callCount == 1)
    }

    @Test func rejectionOfAnOlderTokenReusesTheNewOne() async throws {
        let refresher = FakeRefresher()
        let coordinator = TokenCoordinator(initial: credential(expiresIn: 30), store: InMemoryCredentialStore(), refresher: refresher, clock: clock)
        _ = try await coordinator.accessToken() // refreshed to a2
        clock.advance(by: .seconds(120))
        #expect(try await coordinator.tokenAfterRejection(of: "a1") == "a2")
        #expect(refresher.callCount == 1)
    }

    @Test func invalidGrantDropsTokensAndStopsCallingCanvas() async throws {
        let store = InMemoryCredentialStore(credential(expiresIn: 30)), refresher = FakeRefresher(failure: TokenEndpointError.invalidGrant)
        let coordinator = TokenCoordinator(initial: credential(expiresIn: 30), store: store, refresher: refresher, clock: clock)
        await #expect(throws: AuthError.reauthRequired) { try await coordinator.accessToken() }
        await #expect(throws: AuthError.reauthRequired) { try await coordinator.accessToken() }
        #expect(refresher.callCount == 1 && store.credential == nil && store.log == ["deleted"])
        #expect(await coordinator.needsReauth)
    }

    @Test(arguments: [TransportError.offline, TokenEndpointError.rejected(status: 503)] as [any Error & Sendable])
    func transientFailureKeepsTokens(_ failure: any Error & Sendable) async throws {
        let store = InMemoryCredentialStore(credential(expiresIn: 30)), refresher = FakeRefresher(failure: failure)
        let coordinator = TokenCoordinator(initial: credential(expiresIn: 30), store: store, refresher: refresher, clock: clock)
        await #expect(throws: AuthError.transient) { try await coordinator.accessToken() }
        let needsReauth = await coordinator.needsReauth
        #expect(store.credential != nil && !needsReauth)
    }

    @Test func refreshedTokenRejectedAgainMeansReauthNotALoop() async throws {
        let refresher = FakeRefresher()
        let coordinator = TokenCoordinator(initial: credential(expiresIn: 3000), store: InMemoryCredentialStore(), refresher: refresher, clock: clock)
        #expect(try await coordinator.tokenAfterRejection(of: "a1") == "a2")
        await #expect(throws: AuthError.reauthRequired) { try await coordinator.tokenAfterRejection(of: "a2") }
        #expect(refresher.callCount == 1)
    }
}

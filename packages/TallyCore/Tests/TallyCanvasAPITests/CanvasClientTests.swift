import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyCanvasAPI

/// Rotates the token on every call and counts how many times it was asked to.
/// Shared with `CanvasGatewayTests`.
final class RecordingRefresher: TokenRefreshing, @unchecked Sendable {
    private var calls = 0
    private let lock = NSLock()
    var callCount: Int { lock.withLock { calls } }

    func refresh(_ credential: CanvasCredential) async throws -> CanvasCredential {
        lock.withLock { calls += 1 }
        var next = credential
        next.accessToken = "refreshed-\(calls)"
        next.accessTokenExpiresAt = Date(timeIntervalSince1970: 1_790_604_000)
        return next
    }
}

@Suite("CanvasClient: headers, pagination, auth and retry policy")
struct CanvasClientTests {
    private let host = "canvas.northfield.example"

    private func coordinator(clock: TestClock, refresher: any TokenRefreshing = RecordingRefresher(),
                             store: InMemoryCredentialStore? = nil) -> TokenCoordinator {
        let credential = CanvasCredential(host: host, userID: "4820117", accessToken: "token-1",
                                          refreshToken: "refresh-1", accessTokenExpiresAt: clock.now().addingTimeInterval(3600))
        return TokenCoordinator(initial: credential, store: store ?? InMemoryCredentialStore(credential),
                                refresher: refresher, clock: clock)
    }

    private func fastBackoff() -> BackoffPolicy { BackoffPolicy(base: .milliseconds(1), maxDelay: .milliseconds(5)) }

    @Test func fetchOneReturnsTheReplayedBody() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()))
        let data = try await client.fetchOne(path: "/api/v1/users/self/profile")
        let profile = try ProfileMapper.map(data)
        #expect(profile.name == "Alex Sample")
    }

    @Test func fetchAllPagesFollowsLinkAcrossBothPlannerPages() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()))
        let pages = try await client.fetchAllPages(path: "/api/v1/planner/items",
                                                   query: [("start_date", "2026-09-14"), ("end_date", "2026-11-27"), ("per_page", "100")])
        #expect(pages.count == 2)
        let total = try pages.reduce(0) { try $0 + PlannerItemMapper.map($1, host: host).items.count }
        #expect(total == 178) // 100 + 78, matching the two page files
    }

    @Test func unsafeNextLinkStopsPaginationWithoutFollowingIt() async throws {
        let transport = try ReplayTransport.scenario("pagination/next-link-foreign-host")
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()))
        let pages = try await client.fetchAllPages(path: "/api/v1/courses", query: CanvasQuery.courses())
        #expect(pages.count == 1) // the unsafe `next` is never requested
        let requestCount = await transport.requestCount
        #expect(requestCount == 1)
    }

    @Test func http401WithWWWAuthenticateRefreshesExactlyOnceThenSucceeds() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let refresher = RecordingRefresher()
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock(), refresher: refresher))
        await transport.inject(response: try ReplayTransport.errorResponse("401-invalid-access-token"), times: 1,
                               matching: { $0.url.path == "/api/v1/users/self/profile" })
        let data = try await client.fetchOne(path: "/api/v1/users/self/profile")
        #expect(!data.isEmpty)
        #expect(refresher.callCount == 1)
    }

    @Test func http401WithoutWWWAuthenticateFailsWithoutRefreshing() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let refresher = RecordingRefresher()
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock(), refresher: refresher))
        await transport.inject(response: try ReplayTransport.errorResponse("401-insufficient-scopes"), times: 1,
                               matching: { $0.url.path == "/api/v1/users/self/profile" })
        await #expect(throws: RefreshFailure.unknown) {
            _ = try await client.fetchOne(path: "/api/v1/users/self/profile")
        }
        #expect(refresher.callCount == 0)
    }

    @Test func serverErrorRetriesTwiceThenSucceeds() async throws {
        let transport = try ReplayTransport.persona("flagship")
        await transport.inject(response: try ReplayTransport.errorResponse("500-internal-server-error"), times: 2,
                               matching: { $0.url.path == "/api/v1/users/self/profile" })
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()), backoff: fastBackoff())
        let data = try await client.fetchOne(path: "/api/v1/users/self/profile")
        #expect(!data.isEmpty)
    }

    @Test func serverErrorGivesUpAfterTwoRetries() async throws {
        let transport = try ReplayTransport.persona("flagship")
        await transport.inject(response: try ReplayTransport.errorResponse("500-internal-server-error"), times: 3,
                               matching: { $0.url.path == "/api/v1/users/self/profile" })
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()), backoff: fastBackoff())
        await #expect(throws: RefreshFailure.server) {
            _ = try await client.fetchOne(path: "/api/v1/users/self/profile")
        }
    }

    @Test func rateLimitedRetriesThenSucceeds() async throws {
        let transport = try ReplayTransport.persona("flagship")
        await transport.inject(response: try ReplayTransport.errorResponse("429-rate-limit-exceeded"), times: 2,
                               matching: { $0.url.path == "/api/v1/users/self/profile" })
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()), backoff: fastBackoff())
        let data = try await client.fetchOne(path: "/api/v1/users/self/profile", budget: .seconds(5))
        #expect(!data.isEmpty)
    }
}

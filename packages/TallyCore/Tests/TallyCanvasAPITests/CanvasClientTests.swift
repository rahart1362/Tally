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

    /// R-1: the budget is now measured on the real clock here, so it goes through `TestTimeBudget`
    /// (a sanitizer lane can starve this test for seconds; the default is the same 10 s).
    @Test func serverErrorRetriesTwiceThenSucceeds() async throws {
        let transport = try ReplayTransport.persona("flagship")
        await transport.inject(response: try ReplayTransport.errorResponse("500-internal-server-error"), times: 2,
                               matching: { $0.url.path == "/api/v1/users/self/profile" })
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()), backoff: fastBackoff())
        let data = try await client.fetchOne(path: "/api/v1/users/self/profile", budget: TestTimeBudget.seconds(10))
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

    /// R-1: as above, the real-clock budget goes through `TestTimeBudget`. Before R-1 the budget
    /// was never measured, and under `make core-tsan` this test once took 9.5 s.
    @Test func rateLimitedRetriesThenSucceeds() async throws {
        let transport = try ReplayTransport.persona("flagship")
        await transport.inject(response: try ReplayTransport.errorResponse("429-rate-limit-exceeded"), times: 2,
                               matching: { $0.url.path == "/api/v1/users/self/profile" })
        // On a VirtualClock the budget is spent only by the backoff waits, never by how fast the
        // machine runs. On the real clock this test flaked under ThreadSanitizer on CI's 2-vCPU
        // runner: CPU starvation used up the elapsed-time budget that R-1 (CS-08) now enforces
        // (app-core report O7: 54.8 s against 50 s in run 36394287625).
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()), backoff: fastBackoff(),
                                  rng: SeededRandom(seed: 1), clock: VirtualClock(), wallClock: TestClock())
        let data = try await client.fetchOne(path: "/api/v1/users/self/profile", budget: .seconds(5))
        #expect(!data.isEmpty)
    }

    // MARK: - CS-05: resource limits

    @Test func fetchOneRejectsAResponseBodyPastTheConfiguredCap() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()))
        let oversized = HTTPResponse(status: 200, body: Data(count: TallyConfig.maxResponseBodyBytes + 1))
        await transport.inject(response: oversized, times: 1, matching: { $0.url.path == "/api/v1/users/self/profile" })
        await #expect(throws: RefreshFailure.contract) {
            _ = try await client.fetchOne(path: "/api/v1/users/self/profile")
        }
    }

    @Test func fetchOneAcceptsARegularSizedBodyRightAtTheCap() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()))
        let atCap = HTTPResponse(status: 200, body: Data(count: TallyConfig.maxResponseBodyBytes))
        await transport.inject(response: atCap, times: 1, matching: { $0.url.path == "/api/v1/users/self/profile" })
        let data = try await client.fetchOne(path: "/api/v1/users/self/profile")
        #expect(data.count == TallyConfig.maxResponseBodyBytes, "exactly at the cap must still succeed")
    }

    /// Verifies the existing `TallyConfig.maxPagesPerResource` cap: a server that never stops
    /// sending `Link: rel="next"` must not be followed forever (CS-05).
    @Test func fetchAllPagesStopsAtTheConfiguredPageCapEvenWhenLinkNeverStops() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let client = CanvasClient(host: host, transport: transport, tokens: coordinator(clock: TestClock()))
        let endlessNext = HTTPResponse(status: 200, headers: HTTPHeaders(["Link": "<https://\(host)/api/v1/courses?page=2>; rel=\"next\""]),
                                       body: Data("[]".utf8))
        await transport.inject(response: endlessNext, times: TallyConfig.maxPagesPerResource + 10,
                               matching: { $0.url.path == "/api/v1/courses" })
        let pages = try await client.fetchAllPages(path: "/api/v1/courses", query: CanvasQuery.courses())
        #expect(pages.count == TallyConfig.maxPagesPerResource,
                "must stop exactly at TallyConfig.maxPagesPerResource even when the server's Link header never stops")
    }
}

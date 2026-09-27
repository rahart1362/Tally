import Foundation
import Testing
import TallyTestSupport
@testable import TallyCanvasAPI

@Suite("ReplayTransport: manifest-driven fixture replay")
struct ReplayTransportTests {
    private func request(_ host: String, _ path: String, query: String = "") -> HTTPRequest {
        var components = URLComponents()
        components.scheme = "https"; components.host = host; components.path = path
        if !query.isEmpty { components.percentEncodedQuery = query }
        return HTTPRequest(url: components.url!)
    }

    @Test func servesTheRecordedProfileBodyAndHeaders() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let response = try await transport.send(request("canvas.northfield.example", "/api/v1/users/self/profile"))
        #expect(response.status == 200)
        let body = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        #expect(body?["name"] as? String == "Alex Sample")
    }

    @Test func matchesQueryRegardlessOfKeyOrderAndPercentEncoding() async throws {
        let transport = try ReplayTransport.persona("flagship")
        // Same pairs as the recorded courses request, reordered and percent-encoded differently.
        let query = "per_page=100&include%5B%5D=teachers&include%5B%5D=total_scores&include%5B%5D=term" +
            "&include%5B%5D=current_grading_period_scores&enrollment_state=active"
        let response = try await transport.send(request("canvas.northfield.example", "/api/v1/courses", query: query))
        #expect(response.status == 200)
        #expect(!response.body.isEmpty)
    }

    @Test func returnsLinkHeaderForAPagedRoute() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let query = "start_date=2026-09-14&end_date=2026-11-27&per_page=100"
        let response = try await transport.send(request("canvas.northfield.example", "/api/v1/planner/items", query: query))
        #expect(response.headers["Link"]?.contains("rel=\"next\"") == true)
    }

    @Test func rebasedDateWindowStillMatchesViaQueryMatchWildcard() async throws {
        let transport = try ReplayTransport.persona("flagship")
        // Different start/end dates than the recording: only query_match's '*' wildcard can match this.
        let query = "start_date=2027-01-01&end_date=2027-03-01&per_page=100"
        let response = try await transport.send(request("canvas.northfield.example", "/api/v1/planner/items", query: query))
        #expect(response.status == 200 && !response.body.isEmpty)
    }

    @Test func unknownRouteIs404() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let response = try await transport.send(request("canvas.northfield.example", "/api/v1/courses/999999/assignment_groups"))
        #expect(response.status == 404)
    }

    @Test func requestLogCountsEveryCall() async throws {
        let transport = try ReplayTransport.persona("empty")
        #expect(await transport.requestCount == 0)
        _ = try await transport.send(request("canvas.lakeshore.example", "/api/v1/users/self/profile"))
        _ = try await transport.send(request("canvas.lakeshore.example", "/nonexistent"))
        let log = await transport.requests()
        let count = await transport.requestCount
        #expect(log.count == 2 && count == 2)
    }

    @Test func injectedLatencyDelaysBeforeTheNormalResponse() async throws {
        let transport = try ReplayTransport.persona("empty")
        await transport.inject(latency: .milliseconds(30), times: 1, matching: { _ in true })
        let start = ContinuousClock.now
        let response = try await transport.send(request("canvas.lakeshore.example", "/api/v1/users/self/profile"))
        #expect(ContinuousClock.now - start >= .milliseconds(30))
        #expect(response.status == 200) // falls through to the normal replayed body
    }

    @Test func injectedResponseIsConsumedExactlyOnce() async throws {
        let transport = try ReplayTransport.persona("empty")
        await transport.inject(response: HTTPResponse(status: 500), times: 1, matching: { _ in true })
        let first = try await transport.send(request("canvas.lakeshore.example", "/api/v1/users/self/profile"))
        let second = try await transport.send(request("canvas.lakeshore.example", "/api/v1/users/self/profile"))
        #expect(first.status == 500 && second.status == 200)
    }

    @Test func canned401WithWWWAuthenticateMeansTokenRejected() throws {
        let response = try ReplayTransport.errorResponse("401-invalid-access-token")
        #expect(response.status == 401 && response.headers["WWW-Authenticate"] != nil)
        #expect(ResponseClassifier.classify(response) == .tokenRejected)
    }

    @Test func canned401WithoutWWWAuthenticateMeansInsufficientScope() throws {
        let response = try ReplayTransport.errorResponse("401-insufficient-scopes")
        #expect(response.status == 401 && response.headers["WWW-Authenticate"] == nil)
        #expect(ResponseClassifier.classify(response) == .insufficientScope)
    }

    @Test func canned429IsRateLimited() throws {
        let response = try ReplayTransport.errorResponse("429-rate-limit-exceeded")
        #expect(ResponseClassifier.classify(response) == .rateLimited)
    }

    @Test func canned403RateLimitedIsRateLimitedNotForbidden() throws {
        let response = try ReplayTransport.errorResponse("403-rate-limit-exceeded")
        #expect(ResponseClassifier.classify(response) == .rateLimited)
    }

    @Test func canned403UnauthorizedIsForbidden() throws {
        let response = try ReplayTransport.errorResponse("403-unauthorized")
        #expect(ResponseClassifier.classify(response) == .forbidden)
    }

    @Test func canned5xxIsServerError() throws {
        let response = try ReplayTransport.errorResponse("500-internal-server-error")
        #expect(ResponseClassifier.classify(response) == .serverError)
    }

    @Test func scenarioLoaderServesA401Body() async throws {
        let transport = try ReplayTransport.scenario("profile/token-invalid-401")
        let response = try await transport.send(request("canvas.northfield.example", "/api/v1/users/self/profile"))
        #expect(response.status == 401)
    }

    @Test func parentObserverAccountRoutesAreScopedByHost() async throws {
        let northfield = try ReplayTransport.personaAccount("parent-observer", host: "canvas.northfield.example")
        let response = try await northfield.send(request("canvas.northfield.example", "/api/v1/users/self/observees",
                                                          query: "include%5B%5D=avatar_url&per_page=100"))
        #expect(response.status == 200)
    }
}

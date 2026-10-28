import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyCanvasAPI

/// Item 3 (LIVE-FIX-2/LIVE-3, `docs/pmo/reviews/live1-report.md`): `If-None-Match` per endpoint
/// and request, reusing the cached body on a 304. Canvas sends `ETag` + `must-revalidate` on its
/// cacheable GETs; `fixtures/canvas`'s own replayed responses never carry one, so these tests
/// inject ad hoc responses rather than reusing a persona's fixtures.
@Suite("CanvasClient: ETag conditional requests (item 3)")
struct ETagCacheTests {
    private let host = "canvas.northfield.example"

    private func client(_ transport: ReplayTransport, etags: any ETagStore) -> CanvasClient {
        let clock = TestClock()
        let credential = CanvasCredential(host: host, userID: "4820117", accessToken: "token-1", refreshToken: "refresh-1",
                                          accessTokenExpiresAt: clock.now().addingTimeInterval(3600))
        let tokens = TokenCoordinator(initial: credential, store: InMemoryCredentialStore(credential),
                                      refresher: RecordingRefresher(), clock: clock)
        return CanvasClient(host: host, transport: transport, tokens: tokens, etags: etags)
    }

    @Test("First response with no cache entry carries no If-None-Match; a fresh ETag is stored")
    func firstRequestSendsNoConditionalHeaderAndStoresTheETag() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let etag = "\"v1\""
        let body = Data(#"{"id":"4820117","name":"Alex Sample"}"#.utf8)
        await transport.inject(response: HTTPResponse(status: 200, headers: HTTPHeaders(["ETag": etag]), body: body),
                               times: 1, matching: { $0.url.path == "/api/v1/users/self/profile" })
        let etags = InMemoryETagStore()
        let data = try await self.client(transport, etags: etags).fetchOne(path: "/api/v1/users/self/profile")
        #expect(data == body)

        let sent = await transport.requests()
        #expect(sent.first?.headers["If-None-Match"] == nil)
        let key = try #require(sent.first?.url.absoluteString)
        #expect(await etags.entry(for: key) == ETagCacheEntry(etag: etag, body: body))
    }

    @Test("A 304 to the stored ETag reuses the cached body -- byte savings: the 304 carries none")
    func a304ReusesTheCachedBody() async throws {
        let transport = try ReplayTransport.persona("flagship")
        let etag = "\"v1\""
        let body = Data(#"{"id":"4820117","name":"Alex Sample"}"#.utf8)
        await transport.inject(response: HTTPResponse(status: 200, headers: HTTPHeaders(["ETag": etag]), body: body),
                               times: 1, matching: { $0.url.path == "/api/v1/users/self/profile" })
        // The 304's own body is empty (RFC 9110 §15.4.5): nothing to send back once the client
        // already has the representation.
        await transport.inject(response: HTTPResponse(status: 304), times: 1,
                               matching: { $0.url.path == "/api/v1/users/self/profile" })

        let etags = InMemoryETagStore()
        let client = self.client(transport, etags: etags)
        let first = try await client.fetchOne(path: "/api/v1/users/self/profile")
        #expect(first == body)
        let second = try await client.fetchOne(path: "/api/v1/users/self/profile")
        #expect(second == body, "the cached body is reused, byte-identical to the first fetch")

        let sent = await transport.requests()
        #expect(sent.count == 2)
        #expect(sent.last?.headers["If-None-Match"] == etag, "the second request sent the stored ETag back")
    }

    @Test("A write (perform, never GET) neither sends nor stores an ETag")
    func aNonGETRequestIsNeverConditionalOrCached() async throws {
        let transport = try ReplayTransport.scenario("profile/token-invalid-401") // any scenario; only the method matters here
        let etags = InMemoryETagStore()
        let response = HTTPResponse(status: 422, body: Data(#"{"errors":[{"message":"bad code"}]}"#.utf8))
        await transport.inject(response: response, times: 1, matching: { $0.method == .post })
        let result = try await self.client(transport, etags: etags)
            .perform(method: .post, path: "/api/v1/users/self/observees/self", contentType: "application/json")
        #expect(result.status == 422)
        let sent = await transport.requests()
        #expect(sent.first?.headers["If-None-Match"] == nil)
        #expect(etags.all.isEmpty, "a write is never cached either")
    }
}

import Testing

/// Pure, no live server needed (runs under plain `make core-test`): the item-5 companion fix
/// (`LiveURLSessionTransport.swift`) that rewrites a `Link` header's URLs back to https/no-port
/// before `CanvasClient` ever sees them, so this dev stack's http `next` link does not trip
/// `PageURLPolicy`'s now-throwing rejection the way a production, TLS-only Canvas never would.
@Suite("LiveURLSessionTransport: Link header rewritten to https (item 5 companion fix)")
struct LiveURLSessionTransportTests {
    @Test func rewritesHTTPAndDropsAForcedPortOnEveryURLInTheHeader() {
        let header = "<http://127.0.0.1:8790/api/v1/courses?page=1>; rel=\"current\"," +
            "<http://127.0.0.1:8790/api/v1/courses?page=2>; rel=\"next\""
        let rewritten = LiveURLSessionTransport.rewriteLinkHeaderToHTTPS(header)
        #expect(rewritten == "<https://127.0.0.1/api/v1/courses?page=1>; rel=\"current\"," +
               "<https://127.0.0.1/api/v1/courses?page=2>; rel=\"next\"")
    }

    @Test func leavesAnAlreadyHTTPSLinkUnchangedApartFromTheForcedPort() {
        let header = "<https://canvas.example:8790/api/v1/courses?page=2>; rel=\"next\""
        #expect(LiveURLSessionTransport.rewriteLinkHeaderToHTTPS(header) == "<https://canvas.example/api/v1/courses?page=2>; rel=\"next\"")
    }

    @Test func passesThroughAHeaderWithNoLinksAtAllUnchanged() {
        #expect(LiveURLSessionTransport.rewriteLinkHeaderToHTTPS("") == "")
    }
}

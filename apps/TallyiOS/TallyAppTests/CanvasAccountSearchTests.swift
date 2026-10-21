import Foundation
import Testing
import TallyCanvasAPI
@testable import TallyFeatures

/// SEC1-16 (verified): `CanvasAccountSearch` sent `Accept: application/json`, but
/// `AccountSearchDTO.id` is a non-optional `String` because Tally asks for canvas-string-ids --
/// the same header `CanvasClient.acceptHeader` names for the authenticated API. A numeric `id`
/// under the plain header would fail every row's decode.
@Suite("CanvasAccountSearch: the search request")
struct CanvasAccountSearchTests {
    @Test("search(name:) sends the canvas-string-ids Accept header, not a plain application/json")
    func sendsCanvasStringIDsAcceptHeader() async throws {
        let transport = AcceptHeaderRecordingTransport(response: HTTPResponse(status: 200, body: Data("[]".utf8)))
        let search = CanvasAccountSearch(transport: transport)
        _ = try await search.search(name: "Northfield")
        let sent = await transport.lastRequest
        #expect(sent?.headers["Accept"] == CanvasClient.acceptHeader)
        #expect(sent?.headers["Accept"] != "application/json", "the plain header fails to decode a numeric id")
    }
}

/// Named distinctly from the shared `RecordingTransport` in `AccountLifecycleTestSupport.swift`
/// (an `internal` type, visible module-wide in this test target) -- that one 404s anything but
/// `/login/oauth2/token`, which would not exercise this request at all.
private actor AcceptHeaderRecordingTransport: HTTPTransport {
    private let response: HTTPResponse
    private(set) var lastRequest: HTTPRequest?

    init(response: HTTPResponse) {
        self.response = response
    }

    func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
        lastRequest = request
        return response
    }
}

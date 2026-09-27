import Foundation
import Testing
import TallyCanvasAPI
import TallyTestSupport
@testable import TallyFeatures

/// UX-WP-09. Verifies `CanvasTokenExchange` — the real `TokenExchanging`
/// conformance, as opposed to the hand-written fakes
/// `SignInHandoffViewModelTests` uses — actually performs the
/// `TransportError` → `.networkFailure` and `TokenEndpointError` →
/// `.rejected` classification `TokenExchangeError`'s doc comment promises,
/// never leaking the underlying `TallyCanvasAPI` error type itself.
@MainActor
@Suite("CanvasTokenExchange (UX-WP-09)")
struct CanvasTokenExchangeTests {
    private let redirect = URL(string: "https://tally-app.dev/oauth/callback")!
    private let endpoint = TokenEndpoint(host: "canvas.northfield.example", clientID: "170000000000001")

    @Test("A transport-level failure is classified as networkFailure, not leaked as TransportError")
    func transportFailureIsClassified() async {
        let exchange = CanvasTokenExchange(endpoint: endpoint, transport: ThrowingTransport(error: .offline))
        await #expect(throws: TokenExchangeError.networkFailure) {
            _ = try await exchange.exchange(code: "c0de", verifier: "v", redirectURI: redirect)
        }
    }

    @Test("A rejected token response is classified as rejected, not leaked as TokenEndpointError")
    func rejectedResponseIsClassified() async {
        let transport = CannedResponseTransport(response: HTTPResponse(status: 400, body: Data(#"{"error":"invalid_grant"}"#.utf8)))
        let exchange = CanvasTokenExchange(endpoint: endpoint, transport: transport)
        await #expect(throws: TokenExchangeError.rejected) {
            _ = try await exchange.exchange(code: "c0de", verifier: "v", redirectURI: redirect)
        }
    }

    @Test("A successful exchange returns the real credential")
    func successfulExchangeReturnsCredential() async throws {
        let body = #"{"access_token":"a1","token_type":"Bearer","user":{"id":"42"},"refresh_token":"r1","expires_in":3600}"#
        let transport = CannedResponseTransport(response: HTTPResponse(status: 200, body: Data(body.utf8)))
        let exchange = CanvasTokenExchange(endpoint: endpoint, transport: transport)
        let credential = try await exchange.exchange(code: "c0de", verifier: "v", redirectURI: redirect)
        #expect(credential.accessToken == "a1")
        #expect(credential.userID == "42")
    }
}

private struct ThrowingTransport: HTTPTransport {
    let error: TransportError
    func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
        throw error
    }
}

private struct CannedResponseTransport: HTTPTransport {
    let response: HTTPResponse
    func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
        response
    }
}

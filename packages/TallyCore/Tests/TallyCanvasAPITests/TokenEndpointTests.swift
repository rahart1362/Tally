import Foundation
import Testing
import TallyTestSupport
@testable import TallyCanvasAPI

@Suite("Token endpoint (public PKCE client)")
struct TokenEndpointTests {
    let endpoint = TokenEndpoint(host: "canvas.northfield.example", clientID: "170000000000001")
    let clock = TestClock()
    let redirect = URL(string: "https://tally-app.dev/oauth/callback")!

    private func ok(_ json: String) -> HTTPResponse { HTTPResponse(status: 200, body: Data(json.utf8)) }
    private func form(_ request: HTTPRequest) -> [String: String] {
        let text = String(decoding: request.body ?? Data(), as: UTF8.self)
        return Dictionary(uniqueKeysWithValues: text.split(separator: "&").map {
            let kv = $0.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding! }
            return (kv[0], kv.count > 1 ? kv[1] : "")
        })
    }

    @Test func codeExchangeSendsVerifierAndNoSecret() {
        let request = endpoint.request(for: .authorizationCode(code: "c0de", verifier: "v/er+ifier", redirectURI: redirect))
        #expect(request.method == .post && request.url.absoluteString == "https://canvas.northfield.example/login/oauth2/token")
        #expect(request.headers["content-type"] == "application/x-www-form-urlencoded")
        #expect(form(request) == ["client_id": "170000000000001", "grant_type": "authorization_code", "code": "c0de",
                                  "code_verifier": "v/er+ifier", "redirect_uri": "https://tally-app.dev/oauth/callback"])
        let raw = String(decoding: request.body!, as: UTF8.self)
        #expect(!raw.contains("client_secret") && !raw.contains("replace_tokens") && raw.contains("v%2Fer%2Bifier"))
    }

    @Test func refreshSendsOnlyRefreshToken() {
        #expect(form(endpoint.request(for: .refresh(refreshToken: "r1"))) ==
                ["client_id": "170000000000001", "grant_type": "refresh_token", "refresh_token": "r1"])
    }

    @Test func parsesInitialGrantWithNumericUserID() throws {
        let c = try endpoint.credential(from: ok(#"{"access_token":"a1","token_type":"Bearer","user":{"id":42,"name":"Sample Student"},"refresh_token":"r1","expires_in":3600,"canvas_region":"us-east-1"}"#),
                                        previous: nil, now: clock.now())
        #expect(c.userID == "42" && c.accessToken == "a1" && c.refreshToken == "r1")
        #expect(c.accessTokenExpiresAt == clock.now().addingTimeInterval(3600))
        #expect(c.isAccessTokenUsable(now: clock.now()) && !c.isAccessTokenUsable(now: clock.now().addingTimeInterval(3550)))
    }

    @Test func rotatedRefreshTokenReplacesOldMissingOneIsKept() throws {
        let first = try endpoint.credential(from: ok(#"{"access_token":"a1","user":{"id":"42"},"refresh_token":"r1","expires_in":7200}"#), previous: nil, now: clock.now())
        let rotated = try endpoint.credential(from: ok(#"{"access_token":"a2","user":{"id":42},"refresh_token":"r2","expires_in":7200}"#), previous: first, now: clock.now())
        #expect(rotated.refreshToken == "r2" && rotated.accessToken == "a2")
        let kept = try endpoint.credential(from: ok(#"{"access_token":"a3","user":{"id":42},"expires_in":3600}"#), previous: rotated, now: clock.now())
        #expect(kept.refreshToken == "r2")
    }

    @Test func errorsMapToReauthOrRejection() {
        let previous = CanvasCredential(host: endpoint.host, userID: "42", accessToken: "a", refreshToken: "r", accessTokenExpiresAt: clock.now())
        #expect(throws: TokenEndpointError.invalidGrant) {
            try endpoint.credential(from: HTTPResponse(status: 400, body: Data(#"{"error":"invalid_grant","error_description":"refresh_token not found"}"#.utf8)), previous: previous, now: clock.now())
        }
        #expect(throws: TokenEndpointError.rejected(status: 500)) {
            try endpoint.credential(from: HTTPResponse(status: 500), previous: previous, now: clock.now())
        }
        #expect(throws: TokenEndpointError.malformed) { try endpoint.credential(from: ok("{}"), previous: nil, now: clock.now()) }
        #expect(throws: TokenEndpointError.malformed) {
            try endpoint.credential(from: ok(#"{"access_token":"a","user":{"id":1}}"#), previous: nil, now: clock.now()) // no refresh token at all
        }
        #expect(throws: TokenEndpointError.userMismatch) {
            try endpoint.credential(from: ok(#"{"access_token":"a","user":{"id":99},"refresh_token":"r"}"#), previous: previous, now: clock.now())
        }
    }

    @Test func revokeUsesBearerAndCredentialNeverPrintsTokens() {
        let c = CanvasCredential(host: endpoint.host, userID: "42", accessToken: "SECRET-A", refreshToken: "SECRET-R", accessTokenExpiresAt: clock.now())
        let revoke = endpoint.revokeRequest(for: c)
        #expect(revoke.method == .delete && revoke.headers["authorization"] == "Bearer SECRET-A")
        for text in [String(describing: c), String(reflecting: c), "\(c)"] {
            #expect(!text.contains("SECRET"))
        }
    }
}

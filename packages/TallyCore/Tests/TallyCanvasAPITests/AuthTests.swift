import Foundation
import Testing
import TallyTestSupport
@testable import TallyCanvasAPI

@Suite("Canvas sign-in: PKCE, state and callback")
struct AuthTests {
    let redirect = URL(string: "https://tally-app.dev/oauth/callback")!
    let clock = TestClock()

    private func begin(seed: UInt64 = 1, forceLogin: Bool = false) -> AuthorizationRequest {
        var rng = SeededRandom(seed: seed)
        return .begin(host: "canvas.northfield.example", clientID: "170000000000001",
                      redirectURI: redirect, now: clock.now(), forceLogin: forceLogin, using: &rng)
    }

    @Test func rfc7636AppendixBVector() {
        #expect(PKCEPair.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
                == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func verifierAndStateAreWellFormedAndUnpredictable() {
        var system = SystemRandomNumberGenerator()
        let a = PKCEPair.make(using: &system), b = PKCEPair.make(using: &system)
        let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        #expect(a.verifier.count == 43 && a.verifier.allSatisfy(unreserved.contains))
        #expect(a != b)
        #expect(begin(seed: 1).state != begin(seed: 2).state)
    }

    @Test func authorizeURLCarriesExactlyTheExpectedParameters() throws {
        let request = begin(forceLogin: true)
        let parts = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        #expect(parts.scheme == "https" && parts.host == "canvas.northfield.example" && parts.path == "/login/oauth2/auth")
        let q = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(q == ["client_id": "170000000000001", "response_type": "code",
                      "redirect_uri": "https://tally-app.dev/oauth/callback", "state": request.state,
                      "code_challenge": request.pkce.challenge, "code_challenge_method": "S256", "force_login": "1"])
        #expect(!request.url.absoluteString.contains("client_secret"))
        #expect(!begin().url.absoluteString.contains("force_login"))
    }

    @Test func validCallbackYieldsCode() throws {
        let request = begin()
        let url = URL(string: "https://tally-app.dev/oauth/callback?code=abc123&state=\(request.state)")!
        #expect(try OAuthCallback.code(from: url, for: request, now: clock.now()) == "abc123")
    }

    @Test(arguments: [
        ("https://evil.test/oauth/callback?code=x&state=S", OAuthCallbackError.wrongRedirect),
        ("http://tally-app.dev/oauth/callback?code=x&state=S", .wrongRedirect),
        ("https://tally-app.dev/other?code=x&state=S", .wrongRedirect),
        ("https://tally-app.dev/oauth/callback?code=x&state=forged", .stateMismatch),
        ("https://tally-app.dev/oauth/callback?code=x", .stateMismatch),
        ("https://tally-app.dev/oauth/callback?error=access_denied&state=S", .accessDenied),
        ("https://tally-app.dev/oauth/callback?error=server_error&state=S", .providerError),
        ("https://tally-app.dev/oauth/callback?state=S", .missingCode),
    ])
    func rejectsBadCallbacks(_ template: String, _ expected: OAuthCallbackError) {
        let request = begin()
        let url = URL(string: template.replacingOccurrences(of: "state=S", with: "state=\(request.state)"))!
        #expect(throws: expected) { try OAuthCallback.code(from: url, for: request, now: clock.now()) }
    }

    @Test func expiresAfterTenMinutes() {
        let request = begin()
        let url = URL(string: "https://tally-app.dev/oauth/callback?code=x&state=\(request.state)")!
        #expect(throws: OAuthCallbackError.expired) {
            try OAuthCallback.code(from: url, for: request, now: clock.now().addingTimeInterval(600))
        }
    }

    @Test func stateIsSingleUse() async {
        let pending = PendingAuthorizations(), request = begin()
        await pending.insert(request)
        #expect(await pending.consume(state: request.state) == request)
        #expect(await pending.consume(state: request.state) == nil)
    }

    @Test(arguments: [
        ("canvas.northfield.example", "canvas.northfield.example"),
        ("  HTTPS://Canvas.Northfield.Example/login/canvas?x=1 ", "canvas.northfield.example"),
        ("http://northfield.instructure.com/", "northfield.instructure.com"),
        ("northfield.instructure.com.", "northfield.instructure.com"),
    ])
    func normalizesSchoolAddress(_ input: String, _ expected: String) throws {
        #expect(try InstitutionHost.normalize(input) == expected)
    }

    @Test(arguments: [
        ("", InstitutionHostError.empty), ("northfield", .invalid), ("canvas..example", .invalid),
        ("-bad.example", .invalid), ("cänvas.example", .invalid), ("user@canvas.example", .invalid),
        ("canvas.example:8443", .invalid), ("192.168.0.10", .notAllowed),
    ])
    func rejectsBadSchoolAddresses(_ input: String, _ expected: InstitutionHostError) {
        #expect(throws: expected) { try InstitutionHost.normalize(input) }
    }
}

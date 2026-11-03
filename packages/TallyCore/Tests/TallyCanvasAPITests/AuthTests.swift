import Foundation
import Testing
import TallyDomain
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
        let parts = try #require(URLComponents(url: try request.url, resolvingAgainstBaseURL: false))
        #expect(parts.scheme == "https" && parts.host == "canvas.northfield.example" && parts.path == "/login/oauth2/auth")
        let q = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(q == ["client_id": "170000000000001", "response_type": "code",
                      "redirect_uri": "https://tally-app.dev/oauth/callback", "state": request.state,
                      "code_challenge": request.pkce.challenge, "code_challenge_method": "S256", "force_login": "1",
                      "scope": AuthorizationRequest.scope])
        #expect(try !request.url.absoluteString.contains("client_secret"))
        #expect(try !begin().url.absoluteString.contains("force_login"))
    }

    /// LIVE-2 finding (`docs/pmo/reviews/live1-report.md`, "Least privilege"): Tally sent no
    /// `scope` parameter, so a `require_scopes` developer key failed authorize with
    /// `invalid_scope`. Item 1: the exact 9 scopes, space-separated, derived from one source
    /// (`CanvasScopes.tally`) so the authorize request and the endpoint catalogue can't drift.
    @Test func authorizeURLScopeIsExactlyTheNineCanvasScopesSpaceSeparated() throws {
        let request = begin()
        let parts = try #require(URLComponents(url: try request.url, resolvingAgainstBaseURL: false))
        let scope = try #require(parts.queryItems?.first { $0.name == "scope" }?.value)
        #expect(scope == [
            "url:GET|/api/v1/users/:user_id/profile",
            "url:GET|/api/v1/courses",
            "url:GET|/api/v1/courses/:course_id/assignment_groups",
            "url:GET|/api/v1/courses/:course_id/grading_periods",
            "url:GET|/api/v1/planner/items",
            "url:GET|/api/v1/calendar_events",
            "url:GET|/api/v1/announcements",
            "url:GET|/api/v1/users/:id/colors",
            "url:GET|/api/v1/users/:user_id/observees",
        ].joined(separator: " "))
        #expect(scope.split(separator: " ").count == 9)
    }

    /// LIVE-FIX-1 item 2 (F3's sibling finding, `docs/pmo/reviews/live1-report.md`): a malformed
    /// `host` (here, a caller folding a port into it, same mistake F3 reproduced against
    /// `CanvasClient`) must throw `InstitutionHostError.invalid`, never trap `c.url!`.
    @Test func authorizeURLThrowsOnAMalformedHostInsteadOfTrapping() {
        var rng = SeededRandom(seed: 1)
        let request = AuthorizationRequest.begin(host: "127.0.0.1:8790", clientID: "170000000000001",
                                                 redirectURI: redirect, now: clock.now(), using: &rng)
        #expect(throws: InstitutionHostError.invalid) { try request.url }
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
        // LIVE-FIX-2 (EB-26): the school turned off the account's binding to Tally's developer
        // key (live2-security's live-confirmed authorize redirect); distinct from a student
        // declining consent or any other provider error.
        ("https://tally-app.dev/oauth/callback?error=unauthorized_client&state=S", .schoolDisabled),
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

    @Test("constantTimeEquals is a plain, full equality check -- length-sensitive, content-sensitive, never short-circuiting observably")
    func constantTimeEqualsIsCorrect() {
        #expect(OAuthCallback.constantTimeEquals("abc123", "abc123"))
        #expect(!OAuthCallback.constantTimeEquals("abc123", "abc124"), "one differing byte at the end")
        #expect(!OAuthCallback.constantTimeEquals("abc123", "zbc123"), "one differing byte at the start")
        #expect(!OAuthCallback.constantTimeEquals("abc123", "abc12"), "a shorter right-hand side")
        #expect(!OAuthCallback.constantTimeEquals("abc12", "abc123"), "a shorter left-hand side")
        #expect(!OAuthCallback.constantTimeEquals("", "abc123"))
        #expect(OAuthCallback.constantTimeEquals("", ""))
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

    // MARK: - SEC1-05: per-institution redirect (RFC 9700 §4.4.2 mix-up defence)

    @Test("the same host always derives the same id; two different hosts never collide")
    func institutionIDIsStableAndDistinct() {
        #expect(InstitutionID.derive(host: "canvas.northfield.example") == InstitutionID.derive(host: "canvas.northfield.example"))
        #expect(InstitutionID.derive(host: "canvas.northfield.example") != InstitutionID.derive(host: "canvas.riverside.example"))
        #expect(InstitutionID.derive(host: "canvas.northfield.example").count == TallyConfig.institutionIdHexLength)
    }

    @Test("case never changes the id: the host is normalized before hashing")
    func institutionIDIsCaseInsensitive() {
        #expect(InstitutionID.derive(host: "Canvas.Northfield.EXAMPLE") == InstitutionID.derive(host: "canvas.northfield.example"))
    }

    @Test("the id never leaks the host as readable text")
    func institutionIDIsOpaque() {
        let id = InstitutionID.derive(host: "canvas.northfield.example")
        #expect(!id.lowercased().contains("northfield"))
        #expect(id.allSatisfy { $0.isHexDigit })
    }

    /// The actual mix-up defence (security.md §3.2 item 3; SEC1-05): two institutions' requests
    /// carry two different redirect paths (derived from their own hosts), so a callback meant for
    /// one can never validate against the other's pending request, even with a correct `state` and
    /// `code` -- `OAuthCallback.code(from:for:now:)` needs no new logic for this: path equality
    /// against `request.redirectURI.path` was already exact, so binding the path to the
    /// institution is sufficient on its own.
    @Test func aCallbackPathFromOneInstitutionNeverValidatesAgainstAnothers() throws {
        func redirect(for host: String) -> URL {
            URL(string: "https://tally-app.dev/oauth/callback/\(InstitutionID.derive(host: host))")!
        }
        var rng = SeededRandom(seed: 1)
        let northfield = AuthorizationRequest.begin(host: "canvas.northfield.example", clientID: "170000000000001",
                                                    redirectURI: redirect(for: "canvas.northfield.example"),
                                                    now: clock.now(), using: &rng)
        let riverside = AuthorizationRequest.begin(host: "canvas.riverside.example", clientID: "170000000000002",
                                                   redirectURI: redirect(for: "canvas.riverside.example"),
                                                   now: clock.now(), using: &rng)
        #expect(northfield.redirectURI.path != riverside.redirectURI.path)

        // Riverside's own callback, forged with Northfield's state (the mix-up this defence
        // targets: Canvas sends no `iss`, so without a distinct path the client can't otherwise
        // tell these two authorization servers' callbacks apart).
        let mixedUpCallback = URL(string: "https://tally-app.dev\(riverside.redirectURI.path)?code=stolen&state=\(northfield.state)")!
        #expect(throws: OAuthCallbackError.wrongRedirect) {
            try OAuthCallback.code(from: mixedUpCallback, for: northfield, now: clock.now())
        }
        // Each institution's own, matching callback still works.
        let northfieldCallback = URL(string: "https://tally-app.dev\(northfield.redirectURI.path)?code=abc&state=\(northfield.state)")!
        #expect(try OAuthCallback.code(from: northfieldCallback, for: northfield, now: clock.now()) == "abc")
    }
}

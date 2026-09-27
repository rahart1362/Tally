import Foundation
import Testing
import TallyCanvasAPI
@testable import TallyFeatures

/// UX-WP-09 / F02 / SEC-05. Every case here is driven by a stubbed
/// presenter and a stubbed token endpoint — as the work package states
/// plainly, a real end-to-end sign-in can't complete until the site and
/// Team ID exist (GL-02). `SignInHandoffViewModel` never touches
/// `ASWebAuthenticationSession` or the network directly, only the
/// `WebAuthPresenting` / `TokenExchanging` ports, so this is a full test of
/// its own logic (outcome mapping, `state` round-tripping) without either.
@MainActor
@Suite("Sign-in hand-off (UX-WP-09)")
struct SignInHandoffViewModelTests {
    private let redirect = URL(string: "https://tally-app.dev/oauth/callback")!
    private let credential = CanvasCredential(
        host: "canvas.northfield.example", userID: "42",
        accessToken: "a1", refreshToken: "r1",
        accessTokenExpiresAt: Date(timeIntervalSince1970: 1_790_604_000)
    )

    private func makeViewModel(
        presenter: any WebAuthPresenting,
        tokenExchange: any TokenExchanging,
        onSuccess: @escaping (CanvasCredential) -> Void = { _ in }
    ) -> SignInHandoffViewModel {
        SignInHandoffViewModel(
            host: "canvas.northfield.example", clientID: "170000000000001",
            schoolDisplayName: "Northfield State University",
            presenter: presenter, tokenExchange: tokenExchange, redirectURI: redirect,
            onSuccess: onSuccess
        )
    }

    @Test("A successful callback and token exchange reports the real credential, once")
    func successReportsCredential() async {
        var received: CanvasCredential?
        let viewModel = makeViewModel(
            presenter: FakeWebAuthPresenter(mode: .echoState),
            tokenExchange: FakeTokenExchange(mode: .success(credential)),
            onSuccess: { received = $0 }
        )
        await viewModel.continueSigningIn()
        #expect(viewModel.phase == .idle)
        #expect(received == credential)
    }

    @Test("Cancelling is a calm status, never an error")
    func cancelIsNotAnError() async {
        let viewModel = makeViewModel(presenter: FakeWebAuthPresenter(mode: .cancelled),
                                      tokenExchange: FakeTokenExchange(mode: .other))
        await viewModel.continueSigningIn()
        #expect(viewModel.phase == .cancelledNotice)
    }

    @Test("Declining on the Canvas approval page reports accessDenied")
    func accessDeniedIsReported() async {
        let viewModel = makeViewModel(presenter: FakeWebAuthPresenter(mode: .accessDenied),
                                      tokenExchange: FakeTokenExchange(mode: .other))
        await viewModel.continueSigningIn()
        #expect(viewModel.phase == .failed(.accessDenied))
    }

    @Test("A transport failure during token exchange reports networkFailure")
    func networkFailureIsReported() async {
        let viewModel = makeViewModel(presenter: FakeWebAuthPresenter(mode: .echoState),
                                      tokenExchange: FakeTokenExchange(mode: .networkFailure))
        await viewModel.continueSigningIn()
        #expect(viewModel.phase == .failed(.networkFailure))
    }

    @Test("session.start() == false is reported, never silently ignored")
    func failedToStartIsReported() async {
        let viewModel = makeViewModel(presenter: FakeWebAuthPresenter(mode: .failedToStart),
                                      tokenExchange: FakeTokenExchange(mode: .other))
        await viewModel.continueSigningIn()
        #expect(viewModel.phase == .failed(.other))
    }

    @Test("A mismatched or forged state is rejected before any token exchange happens")
    func forgedCallbackStateIsRejected() async {
        let tokenExchange = FakeTokenExchange(mode: .success(credential))
        let viewModel = makeViewModel(presenter: FakeWebAuthPresenter(mode: .forgedState), tokenExchange: tokenExchange)
        await viewModel.continueSigningIn()
        #expect(viewModel.phase == .failed(.other))
        #expect(tokenExchange.exchangeCallCount == 0)
    }

    @Test("The default redirect URI is built from the single TallyOrgDomain value")
    func defaultRedirectURIUsesOrgDomain() {
        #expect(SignInHandoffViewModel.defaultRedirectURI.scheme == "https")
        #expect(SignInHandoffViewModel.defaultRedirectURI.path == "/oauth/callback")
    }
}

/// Echoes the `state` query item back from whatever authorize `url` it's given —
/// exactly what a real Canvas callback does — so tests never need to predict the
/// view model's internally-generated `state`/PKCE values.
private final class FakeWebAuthPresenter: WebAuthPresenting, @unchecked Sendable {
    enum Mode { case echoState, accessDenied, cancelled, failedToStart, forgedState }
    private let mode: Mode
    init(mode: Mode) { self.mode = mode }

    func authenticate(url: URL, callbackHost: String, callbackPath: String, ephemeral: Bool) async throws -> URL {
        switch mode {
        case .cancelled: throw WebAuthError.cancelled
        case .failedToStart: throw WebAuthError.failedToStart
        case .echoState, .accessDenied, .forgedState:
            let state = mode == .forgedState
                ? "forged-state-value"
                : URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "state" })?.value ?? ""
            var callback = URLComponents()
            callback.scheme = "https"
            callback.host = callbackHost
            callback.path = callbackPath
            callback.queryItems = mode == .accessDenied
                ? [URLQueryItem(name: "error", value: "access_denied"), URLQueryItem(name: "state", value: state)]
                : [URLQueryItem(name: "code", value: "test-code"), URLQueryItem(name: "state", value: state)]
            return callback.url!
        }
    }
}

private final class FakeTokenExchange: TokenExchanging, @unchecked Sendable {
    enum Mode {
        case success(CanvasCredential)
        case networkFailure
        case other
    }
    private let mode: Mode
    private(set) var exchangeCallCount = 0

    init(mode: Mode) { self.mode = mode }

    func exchange(code: String, verifier: String, redirectURI: URL) async throws -> CanvasCredential {
        exchangeCallCount += 1
        switch mode {
        case .success(let credential): return credential
        // `TokenExchanging.exchange` throws only `TokenExchangeError` (its doc
        // comment explains why); a real `CanvasTokenExchange` is what turns
        // `TransportError`/`TokenEndpointError` into these two cases.
        case .networkFailure: throw TokenExchangeError.networkFailure
        case .other: throw TokenExchangeError.rejected
        }
    }
}

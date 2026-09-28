import Foundation
import TallyCanvasAPI

/// What the Welcome stack's sign-in pages need from the platform (UX-WP-08/09), injected by the
/// composition root: the `ASWebAuthenticationSession` presenter, the institution search and
/// enablement list, and the token exchange for a chosen school. The defaults fail honestly
/// (`Unavailable…`), never with fabricated schools or tokens. Main actor, like the pages that use it.
public struct SignInServices {
    public var webAuthPresenter: any WebAuthPresenting
    public var registry: ClientRegistry
    public var institutionSearch: any InstitutionSearching
    /// The token exchange against one school's token endpoint (`host`, `clientID`).
    public var makeTokenExchange: (_ host: String, _ clientID: String) -> any TokenExchanging

    public init(
        webAuthPresenter: (any WebAuthPresenting)? = nil,
        registry: ClientRegistry = ClientRegistry([]),
        institutionSearch: (any InstitutionSearching)? = nil,
        makeTokenExchange: ((_ host: String, _ clientID: String) -> any TokenExchanging)? = nil
    ) {
        self.webAuthPresenter = webAuthPresenter ?? UnavailableWebAuthPresenter()
        self.registry = registry
        self.institutionSearch = institutionSearch ?? UnavailableInstitutionSearch()
        self.makeTokenExchange = makeTokenExchange ?? { _, _ in UnavailableTokenExchange() }
    }

    /// The token exchange over `transport` (`POST /login/oauth2/token`, PKCE public client).
    public static func canvasTokenExchange(transport: any HTTPTransport) -> (String, String) -> any TokenExchanging {
        { host, clientID in CanvasTokenExchange(endpoint: TokenEndpoint(host: host, clientID: clientID), transport: transport) }
    }
}

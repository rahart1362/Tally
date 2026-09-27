import SwiftUI
import TallyCanvasAPI
import TallyDesignSystem

/// Every place the onboarding flow can lead (implementation brief: "Navigation
/// stubs only, with no fake data" grew into UX-WP-08/09 as those work
/// packages landed). Associated values are primitives (never the full
/// `InstitutionMatch`/`ClientRegistration`), so the route stays trivially
/// `Hashable` without asking those `TallyCanvasAPI` types to conform.
enum WelcomeRoute: Hashable {
    case findSchool
    case sampleData
    /// A search result or typed address had no `ClientRegistry` entry
    /// (UX-WP-08; ux-ui.md §3.2.1's "not enabled" row).
    case schoolNotEnabled(school: String)
    /// A chosen school is enabled: on to the sign-in hand-off (UX-WP-09).
    case signIn(host: String, clientID: String, schoolDisplayName: String)
    /// A real `CanvasCredential` was obtained: on to the first-sync skeleton (UX-WP-10).
    case firstSync(schoolDisplayName: String)
    /// The skeleton's publisher reported `.finished`. There is no Dashboard to
    /// route to yet (app-core team's work), so this is as far as onboarding goes.
    case signedIn(schoolDisplayName: String)
}

/// The app's single root view (architecture.md §3.1: the `Tally` target is
/// "composition root only"; everything else, including navigation, lives
/// here in `TallyFeatures`). Composed as `NavigationStack` + the welcome
/// screen + the onboarding destinations, per the iOS 26 navigation shell in
/// ux-ui.md §3.4.
public struct RootView: View {
    @State private var path: [WelcomeRoute] = []
    private let webAuthPresenter: any WebAuthPresenting
    private let tokenExchange: any TokenExchanging

    /// - Parameters:
    ///   - webAuthPresenter: injected by the composition root (architecture.md
    ///     §3.1: "the app's composition root injects adapters through
    ///     protocols") — `TallyFeatures` cannot construct `TallyPlatform`'s
    ///     `WebAuthPresenter` itself. Defaults to `UnavailableWebAuthPresenter`
    ///     so `RootView()` (existing call sites, previews) keeps compiling.
    ///   - tokenExchange: defaults to `UnavailableTokenExchange` until the
    ///     composition root can supply a real `HTTPTransport` (see
    ///     `CanvasAccountSearch`'s identical seam, UX-WP-08).
    public init(
        webAuthPresenter: (any WebAuthPresenting)? = nil,
        tokenExchange: any TokenExchanging = UnavailableTokenExchange()
    ) {
        self.webAuthPresenter = webAuthPresenter ?? UnavailableWebAuthPresenter()
        self.tokenExchange = tokenExchange
    }

    public var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(
                onFindSchool: { path.append(.findSchool) },
                onExploreSampleData: { path.append(.sampleData) }
            )
            .navigationDestination(for: WelcomeRoute.self) { route in
                switch route {
                case .findSchool:
                    SchoolSearchView(
                        viewModel: SchoolSearchViewModel(
                            search: UnavailableInstitutionSearch(),
                            registry: ClientRegistry([]),
                            reachability: PathMonitorReachability()
                        ),
                        onSelectEnabled: { match, registration in
                            path.append(.signIn(host: registration.host, clientID: registration.clientID,
                                               schoolDisplayName: match.name))
                        },
                        onSelectNotEnabled: { school in
                            path.append(.schoolNotEnabled(school: school))
                        }
                    )
                case .sampleData:
                    SampleDataStub()
                case .schoolNotEnabled(let school):
                    SchoolNotEnabledView(school: school, onExploreSampleData: { path = [.sampleData] })
                case .signIn(let host, let clientID, let schoolDisplayName):
                    SignInHandoffView(
                        viewModel: SignInHandoffViewModel(
                            host: host, clientID: clientID, schoolDisplayName: schoolDisplayName,
                            presenter: webAuthPresenter, tokenExchange: tokenExchange,
                            redirectURI: SignInHandoffViewModel.defaultRedirectURI,
                            onSuccess: { _ in
                                // No CredentialStore is wired in yet (SEC WP-SEC-04, a platform-
                                // adapters work package): a real, unpersisted CanvasCredential is
                                // handed here and intentionally goes no further than this navigation.
                                path.append(.firstSync(schoolDisplayName: schoolDisplayName))
                            }
                        ),
                        onChooseDifferentSchool: { path.removeLast() }
                    )
                case .firstSync(let schoolDisplayName):
                    FirstSyncSkeletonView(
                        viewModel: FirstSyncViewModel(
                            schoolDisplayName: schoolDisplayName,
                            publisher: UnavailableFirstSyncPublisher()
                        ),
                        onRetry: {
                            path.removeLast()
                            path.append(.firstSync(schoolDisplayName: schoolDisplayName))
                        },
                        onFinished: {
                            path.append(.signedIn(schoolDisplayName: schoolDisplayName))
                        }
                    )
                case .signedIn(let schoolDisplayName):
                    SignedInPlaceholder(schoolDisplayName: schoolDisplayName)
                }
            }
        }
    }
}

/// As far as onboarding goes today: a real sign-in completed, but the
/// Dashboard it hands off to is the app-core team's work package.
private struct SignedInPlaceholder: View {
    let schoolDisplayName: String

    var body: some View {
        ContentUnavailableView(
            "Signed in to \(schoolDisplayName)",
            systemImage: "checkmark.circle.fill",
            description: Text("The dashboard and first sync land in a later milestone.")
        )
        .background(TallyColor.bgCanvas)
        .navigationTitle("Welcome")
        .navigationBarTitleDisplayMode(.large)
    }
}

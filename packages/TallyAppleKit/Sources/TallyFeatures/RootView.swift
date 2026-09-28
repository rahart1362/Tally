import SwiftUI
import TallyCanvasAPI
import TallyDesignSystem

/// Every place the onboarding flow can lead *inside* the welcome `NavigationStack` (plain pushed
/// pages only). Associated values are primitives (never the full `InstitutionMatch`/
/// `ClientRegistration`), so the route stays trivially `Hashable` without asking those
/// `TallyCanvasAPI` types to conform.
///
/// ASC-14's "Explore with Sample Data" is deliberately **not** a case here: sample data is a
/// sibling root (see `RootView`'s doc comment for why a pushed `TabView` is never allowed).
enum WelcomeRoute: Hashable {
    case findSchool
    /// A search result or typed address had no `ClientRegistry` entry
    /// (UX-WP-08; ux-ui.md §3.2.1's "not enabled" row).
    case schoolNotEnabled(school: String)
    /// A chosen school is enabled: on to the sign-in hand-off (UX-WP-09).
    case signIn(host: String, clientID: String, schoolDisplayName: String)
    /// A real `CanvasCredential` was obtained: on to the first-sync skeleton (UX-WP-10).
    case firstSync(schoolDisplayName: String)
    /// The skeleton's publisher reported `.finished`. There is no signed-in Home to switch to
    /// yet, so this is as far as onboarding goes.
    case signedIn(schoolDisplayName: String)
}

/// The app's single root view (architecture.md §3.1: the `Tally` target is
/// "composition root only"; everything else, including navigation, lives
/// here in `TallyFeatures`). The welcome root is a `NavigationStack` + the
/// welcome screen + the onboarding destinations, per the iOS 26 navigation
/// shell in ux-ui.md §3.4.
///
/// ASC-14 "Explore with Sample Data" is a **sibling root**, never a `navigationDestination` push.
/// `SampleDataRootView` contains `TabShellView`, and `TabShellView` is a `TabView`: CI (runs
/// 36348080137 → 36353526769, five configurations bisected one variable at a time) proved that a
/// `TabView` does not reliably render when it is the content of a page *pushed* onto a
/// `NavigationStack` (the app simply stayed on Welcome), while the exact same content shown as a
/// root works (2d3131f, run 36354897417). Rule: `TabView` and `NavigationStack` appear only as a
/// root, or as a tab's root inside the root `TabView`.
public struct RootView: View {
    @State private var path: [WelcomeRoute] = []
    @State private var isExploringSampleData = false
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
        if isExploringSampleData {
            SampleDataRootView(onExit: { isExploringSampleData = false })
        } else {
            NavigationStack(path: $path) {
                WelcomeView(
                    onFindSchool: { path.append(.findSchool) },
                    onExploreSampleData: { isExploringSampleData = true }
                )
                .navigationDestination(for: WelcomeRoute.self) { route in
                    destination(for: route)
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for route: WelcomeRoute) -> some View {
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
        case .schoolNotEnabled(let school):
            // A root switch, like Welcome's own button: the sample shell is never pushed.
            SchoolNotEnabledView(school: school, onExploreSampleData: {
                path = []
                isExploringSampleData = true
            })
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

/// As far as onboarding goes today: a real sign-in completed, but the signed-in Home root it
/// hands off to lands with the sign-in first-sync step (perf-app-runtime.md §7 step 9).
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

import SwiftUI
import TallyCanvasAPI
import TallyDesignSystem

/// Every place the onboarding flow can lead *inside* the welcome `NavigationStack`: plain pushed
/// pages only. Associated values are primitives (never the full `InstitutionMatch`/
/// `ClientRegistration`), so the route stays trivially `Hashable` without asking those
/// `TallyCanvasAPI` types to conform.
///
/// ASC-14's "Explore with Sample Data" is deliberately **not** a case here: sample data is a root
/// route (`RootRoute.sample`), because the Home shell is a `TabView` and a pushed `TabView` does
/// not render (see `HomeShellView`).
enum WelcomeRoute: Hashable {
    case findSchool
    /// A search result or typed address had no `ClientRegistry` entry
    /// (UX-WP-08; ux-ui.md §3.2.1's "not enabled" row).
    case schoolNotEnabled(school: String)
    /// A chosen school is enabled: on to the sign-in hand-off (UX-WP-09).
    case signIn(host: String, clientID: String, schoolDisplayName: String)
    /// A real `CanvasCredential` was obtained: on to the first-sync skeleton (UX-WP-10).
    case firstSync(schoolDisplayName: String)
    /// The skeleton's publisher reported `.finished`. The root switch to the signed-in Home
    /// (`AppModel.completeSignIn(_:)`) needs the account session from sign-in's first sync
    /// (perf-app-runtime.md §7 step 9), so this plain page is as far as onboarding goes today.
    case signedIn(schoolDisplayName: String)
}

/// `RootRoute.welcome`: onboarding's `NavigationStack` (Welcome, school search, sign-in hand-off,
/// first sync), per the iOS 26 navigation shell in ux-ui.md §3.4. `RootView` creates a new
/// instance each time the route becomes `.welcome`, so the stack's path always starts empty.
struct WelcomeFlowView: View {
    let playsBrandMoment: Bool
    let webAuthPresenter: any WebAuthPresenting
    let tokenExchange: any TokenExchanging
    /// A root switch (`AppModel.enterSample()`), from Welcome and from "school not enabled" alike.
    let onExploreSampleData: () -> Void

    @State private var path: [WelcomeRoute] = []
    @State private var mutationPushesShell = false // MUTATION M1

    init(
        playsBrandMoment: Bool,
        webAuthPresenter: any WebAuthPresenting,
        tokenExchange: any TokenExchanging,
        onExploreSampleData: @escaping () -> Void
    ) {
        self.playsBrandMoment = playsBrandMoment
        self.webAuthPresenter = webAuthPresenter
        self.tokenExchange = tokenExchange
        self.onExploreSampleData = onExploreSampleData
    }

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(
                playsBrandMoment: playsBrandMoment,
                onFindSchool: { path.append(.findSchool) },
                onExploreSampleData: { mutationPushesShell = true } // MUTATION M1: a push, not enterSample()
            )
            .navigationDestination(for: WelcomeRoute.self) { route in
                destination(for: route)
            }
            // MUTATION M1: the Home shell (a TabView) pushed onto the welcome stack.
            .navigationDestination(isPresented: $mutationPushesShell) {
                HomeShellView(
                    snapshot: nil, digest: nil, digestAsOf: nil, freshness: .noCache,
                    banner: AnyView(SampleDataBanner(onExit: { mutationPushesShell = false })),
                    onRefresh: {}
                )
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
            SchoolNotEnabledView(school: school, onExploreSampleData: onExploreSampleData)
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

/// As far as onboarding goes today: a real sign-in completed, but the signed-in Home it hands off
/// to needs the account session from sign-in's first sync (perf-app-runtime.md §7 step 9).
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

import SwiftUI
import TallyCanvasAPI
import TallyDesignSystem

/// `RootRoute.welcome`: onboarding's `NavigationStack` (Welcome, school search, sign-in hand-off,
/// first sync), per the iOS 26 navigation shell in ux-ui.md §3.4. `RootView` creates a new
/// instance each time the route becomes `.welcome`, so the stack's path always starts empty.
///
/// Sign-in's first sync (plan 06 step 9) is the stack's last page, a plain page: when it finishes,
/// `AppModel.finishFirstSync()` switches the root to the signed-in Home, which removes this whole
/// stack. There is no signed-in page inside it.
struct WelcomeFlowView: View {
    let appModel: AppModel
    /// The sign-in pages' platform services (the composition root's).
    let signIn: SignInServices

    @State private var path: [WelcomeRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(
                playsBrandMoment: appModel.playsBrandMoment,
                onFindSchool: { path.append(.findSchool) },
                // A root switch (`AppModel.enterSample()`), from Welcome and from "school not enabled" alike.
                onExploreSampleData: { appModel.enterSample() }
            )
            .navigationDestination(for: WelcomeRoute.self) { route in
                destination(for: route)
            }
        }
    }

    @ViewBuilder
    private func destination(for route: WelcomeRoute) -> some View {
        switch route {
        case .findSchool:
            SchoolSearchView(
                viewModel: SchoolSearchViewModel(
                    search: signIn.institutionSearch,
                    registry: signIn.registry,
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
            SchoolNotEnabledView(school: school, onExploreSampleData: { appModel.enterSample() })
        case .signIn(let host, let clientID, let schoolDisplayName):
            SignInHandoffView(
                viewModel: SignInHandoffViewModel(
                    host: host, clientID: clientID, schoolDisplayName: schoolDisplayName,
                    presenter: signIn.webAuthPresenter, tokenExchange: signIn.makeTokenExchange(host, clientID),
                    redirectURI: SignInHandoffViewModel.defaultRedirectURI,
                    onSuccess: { credential in
                        // perf-app-runtime.md §2.4 S2 → S4: the credential goes to `AppModel` (never into
                        // the navigation path), which builds the first sync; then the page is pushed.
                        appModel.signInSucceeded(credential, target: SignInTarget(
                            host: host, clientID: clientID, schoolDisplayName: schoolDisplayName))
                        path.append(.firstSync(schoolDisplayName: schoolDisplayName))
                    }
                ),
                // Only while this page is on top (plan 06 A8): never traps on an empty path.
                onChooseDifferentSchool: { WelcomePath.pop(route, from: &path) }
            )
        case .firstSync:
            FirstSyncPage(appModel: appModel, onChooseDifferentSchool: { path.removeAll() })
        }
    }
}

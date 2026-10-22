import SwiftUI
import TallyCanvasAPI
import TallyDesignSystem
import TallyStrings

/// `RootRoute.welcome`: onboarding's `NavigationStack` (Welcome, school search, sign-in hand-off,
/// first sync), per the iOS 26 navigation shell in ux-ui.md §3.4. `RootView` creates a new
/// instance each time the route becomes `.welcome`, so the stack's path always starts empty —
/// except FEAT-2's one seeded case: `AppModel.checkMySchool()` leaves a destination
/// (`consumePendingWelcomeRoute()`) that this `init` reads once, so "Check My School"/"Ask My
/// School" lands on the remembered school's own "not enabled" page instead of a blank Welcome.
///
/// Sign-in's first sync (plan 06 step 9) is the stack's last page, a plain page: when it finishes,
/// `AppModel.finishFirstSync()` switches the root to the signed-in Home, which removes this whole
/// stack. There is no signed-in page inside it.
struct WelcomeFlowView: View {
    let appModel: AppModel
    /// The sign-in pages' platform services (the composition root's).
    let signIn: SignInServices

    @State private var path: [WelcomeRoute]

    init(appModel: AppModel, signIn: SignInServices) {
        self.appModel = appModel
        self.signIn = signIn
        let seeded = appModel.consumePendingWelcomeRoute()
        _path = State(initialValue: seeded.map { [$0] } ?? [])
    }

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
        // FP-4 review: School search's "Retry" (and any other unstyled control in this stack)
        // fell back to the system blue tint, 3.20:1 on its background. One tint here, the same
        // fix `HomeShellView`'s `TabView`/`.sheet` already apply, covers the whole onboarding
        // stack — Welcome, school search and its failure states, sign-in hand-off, first sync.
        .tint(TallyColor.accent)
        // SEC1-02 optional variant (security.md §3.2 step 9.4): a one-time, plain notice when the
        // sign-out that just landed here could not confirm Canvas revoked the token — offline, or
        // the revoke failed even after `SignOutUseCase`'s one refresh. This is exactly the screen
        // sign-out already routes to, so it needs no extra plumbing to find the right surface.
        // Never a security control: dismissing it (or a relaunch before it is seen) just ends it,
        // the same as `isSchoolNoticeDismissed`.
        .alert(String(localized: L10n.Welcome.revokeNoticeTitle()), isPresented: Binding(
            get: { appModel.showsSignOutRevokeNotice },
            set: { isPresented in if !isPresented { appModel.dismissSignOutRevokeNotice() } }
        )) {
            Button(String(localized: L10n.Welcome.revokeNoticeOK()), role: .cancel) {}
        } message: {
            Text(L10n.Welcome.revokeNoticeMessage())
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
                    // FEAT-2: persisted locally (never transmitted), so the sample-mode
                    // interstitial and "Check My School" can name this school later.
                    appModel.recordNotEnabledSchool(school)
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
                    // SEC1-05: a redirect distinct to this institution's host (mix-up defence).
                    redirectURI: SignInHandoffViewModel.redirectURI(forHost: host),
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

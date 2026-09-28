import SwiftUI
import TallyCanvasAPI
import TallyDesignSystem
import TallyDomain

/// The app's single root view (architecture.md §3.1: the `Tally` target is "composition root
/// only"; everything else, including navigation, lives here in `TallyFeatures`). It is one
/// `switch` over `AppModel.route` (perf-app-runtime.md §3 item 1):
///
/// - `.launching`: the launch colour (`LaunchPlaceholderView`), while `AppModel.launch()` reads the
///   account directory, the lock setting and the glance off the main actor.
/// - `.welcome`: `WelcomeFlowView`, onboarding's `NavigationStack` of plain pushed pages.
/// - `.sample` and `.signedIn`: `HomeShellView`, the root `TabView` whose tabs own their stacks,
///   over the `HomeModel` the route transition built (sample data, or the account's coordinator).
///
/// ADR 0001's order sits on top of the route (SEC-07): the **privacy cover** (the launch colour,
/// opaque) whenever the lock is on and the scene is not active; the **lock** in place of the route's
/// content while locked, so the cached Home is not even built into the view tree until an unlock;
/// then the **cached render**; then the Home's own launch refresh (the **handshake**).
///
/// **Navigation rule** (CONTRIBUTING.md code-review checklist): `TabView` and `NavigationStack`
/// appear only as a root, or as a tab's root inside the root `TabView` — never inside a pushed
/// destination. CI (runs 36348080137 → 36353526769, five configurations bisected one variable at a
/// time) proved a `TabView` pushed onto a `NavigationStack` never renders (the app simply stayed
/// on Welcome), while the same content as a root works (2d3131f, run 36354897417). This file is
/// the only shipping file allowed to construct the Home shell; CI's hygiene job enforces it.
public struct RootView: View {
    private let appModel: AppModel
    private let signIn: SignInServices
    @Environment(\.scenePhase) private var scenePhase

    /// - Parameters:
    ///   - appModel: the composition root's one `AppModel` (it owns `route` and the lock).
    ///   - signIn: the sign-in pages' platform services, injected by the composition root
    ///     (architecture.md §3.1: "the app's composition root injects adapters through
    ///     protocols"). The defaults fail honestly.
    public init(appModel: AppModel, signIn: SignInServices = SignInServices()) {
        self.appModel = appModel
        self.signIn = signIn
    }

    public var body: some View {
        content
            .overlay {
                if appModel.lock.showsPrivacyCover {
                    LaunchPlaceholderView(role: .privacyCover)
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                appModel.lock.scenePhaseChanged(to: AppLockPolicy.Phase(phase))
            }
            #if DEBUG || TALLY_TEST_HOOKS
            .modifier(LaunchTestHookOverlay(appModel: appModel))
            #endif
    }

    @ViewBuilder
    private var content: some View {
        if appModel.route != .launching, appModel.lock.isLocked {
            LockView(lock: appModel.lock, onSignOut: { appModel.signOut() })
        } else {
            switch appModel.route {
            case .launching:
                LaunchPlaceholderView()
                    .task { await appModel.launch() }
            case .welcome:
                WelcomeFlowView(appModel: appModel, signIn: signIn)
            case .sample:
                if let home = appModel.home {
                    HomeShellView(model: home, banner: AnyView(SampleDataBanner(onExit: { appModel.exitSample() })))
                }
            case .signedIn:
                // The account's Home over its coordinator (`AccountHomeSource`), built by the launch
                // or by the first sync's root switch.
                if let home = appModel.home {
                    HomeShellView(model: home)
                }
            }
        }
    }
}

extension AppLockPolicy.Phase {
    /// SwiftUI's scene phase, in TallyDomain's Foundation-only vocabulary.
    init(_ phase: ScenePhase) {
        switch phase {
        case .active: self = .active
        case .background: self = .background
        default: self = .inactive
        }
    }
}

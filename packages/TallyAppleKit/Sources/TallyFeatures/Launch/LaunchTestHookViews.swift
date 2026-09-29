#if DEBUG || TALLY_TEST_HOOKS
import SwiftUI
import TallyDesignSystem

/// UI-test controls (`LaunchTestHooks`), never in a shipping build: a sign-out button on the
/// signed-in Home (M3-A owns Settings' "Sign Out & Erase") and, with a blocked network, the
/// request count at the first cached paint.
struct LaunchTestHookOverlay: ViewModifier {
    let appModel: AppModel
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if let hooks = appModel.testHooks, hooks.signOutButton || hooks.blockNetwork || hooks.appLock != nil {
                HStack(spacing: TallySpacing.md) {
                    if hooks.blockNetwork {
                        NetworkProbeLabel(probe: LaunchProbe.shared)
                    }
                    if hooks.appLock != nil {
                        // `AppLockUITests`: tells a gesture that did make the app inactive from one that
                        // did not (this bar sits outside the privacy cover).
                        Text("scene: \(Self.name(scenePhase))")
                            .font(TallyTypography.caption)
                            .accessibilityIdentifier("testHook.scenePhase")
                    }
                    Spacer(minLength: 0)
                    if hooks.signOutButton, isSignedInAndUnlocked {
                        Button("Sign Out (test hook)") { appModel.signOut() }
                            .font(TallyTypography.footnote)
                            .accessibilityIdentifier("testHook.signOut")
                    }
                }
                .padding(.horizontal, TallySpacing.screenMargin)
                .padding(.vertical, TallySpacing.xs)
                .background(TallyColor.bgCard)
            }
        }
    }
}

extension LaunchTestHookOverlay {
    private var isSignedInAndUnlocked: Bool {
        guard case .signedIn = appModel.route else { return false }
        return !appModel.lock.isLocked
    }

    static func name(_ phase: ScenePhase) -> String {
        switch phase {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }
}

/// The `emptyScene` hook's window content: nothing but the launch colour's absence, whose task ends
/// `Launch.ToTask` the way `AppModel.launch()` does. `TallyPerfUITests` compares that phase with the
/// real launch's: what is left is the process, the scene and an empty first frame on the simulator.
public struct EmptyLaunchSceneView: View {
    public init() {}

    public var body: some View {
        Color.clear
            .task { LaunchSignpost.enterPhase(nil) }
    }
}

/// "Network blocked · 0 requests before the first paint · N requests": what
/// `LaunchFromCacheUITests` reads.
private struct NetworkProbeLabel: View {
    let probe: LaunchProbe

    var body: some View {
        Text("Network blocked · \(probe.requestsBeforePaint) requests before the first paint · \(probe.requestInstants.count) requests")
            .font(TallyTypography.caption)
            .foregroundStyle(TallyColor.textSecondary)
            .accessibilityIdentifier("testHook.networkProbe")
    }
}
#endif

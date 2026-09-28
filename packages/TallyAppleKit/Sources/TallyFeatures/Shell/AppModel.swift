import Foundation
import TallyDomain
import TallyIntents
import TallySync

/// The app's root routes (perf-app-runtime.md §3 item 1). Exactly one is on screen at a time:
/// `RootView` is a single `switch` over this value, so the Home shell (a `TabView`) is only ever
/// a root and never content pushed onto a `NavigationStack`.
public nonisolated enum RootRoute: Equatable, Sendable {
    /// The first frame: the launch colour, which doubles as the privacy cover (ADR 0001), until
    /// `AppModel.bootstrap()` decides where to go.
    case launching
    /// Onboarding's `NavigationStack` (Welcome, school search, sign-in, first sync): plain pushed
    /// pages only.
    case welcome
    /// ASC-14 "Explore with Sample Data": the Home shell over the bundled flagship persona.
    case sample
    /// A signed-in account's Home shell.
    case signedIn(AccountKey)
}

/// E04: the composition root's top-level app state (architecture.md §3.1: "`AppModel` and
/// `RefreshStatusModel` (`@MainActor @Observable`), consuming `RefreshCoordinator` events"), and
/// the owner of the root route (perf-app-runtime.md §7 step 1).
///
/// Route transitions are explicit methods, and each accepts only the routes it is defined from;
/// any other call is a no-op, so a stray or repeated tap can never land the app in an undefined
/// place:
///
/// | Method | From | To |
/// |---|---|---|
/// | `bootstrap()` | `.launching` | `.welcome` |
/// | `enterSample()` | `.welcome` | `.sample` |
/// | `exitSample()` | `.sample` | `.welcome` |
/// | `completeSignIn(_:)` | `.welcome` | `.signedIn` |
/// | `signOut()` | `.signedIn` | `.welcome` |
///
/// The account's coordinator lives in `accountRuntime` (perf-app-runtime.md §7 step 7), the one
/// owner that the Home, `.backgroundTask` and sign-out share. It holds none today: sign-in's first
/// sync installs one (§7 step 9). `attach(_:)`/`detach()` are the one place the "Refresh Tally"
/// intent's `RefreshIntentBridge` is set and cleared.
@MainActor
@Observable
public final class AppModel {
    public private(set) var route: RootRoute = .launching
    /// Whether the next Welcome appearance plays the brand moment. ux-ui.md §3.2 stage 1: it plays
    /// on "first run and after sign-out only", so it is `true` at launch and after `signOut()`,
    /// and `false` once the student has left Welcome for sample data and comes back.
    public private(set) var playsBrandMoment = true
    public let refreshStatus = RefreshStatusModel()
    /// The signed-in account's one `RefreshCoordinator` owner, shared with `.backgroundTask`
    /// (`AppEnvironment` builds it once and hands it to both).
    public let accountRuntime: AccountRuntime
    /// The Home shell's model: over a `SampleSession` while `route == .sample`, over the account's
    /// coordinator (`AccountHomeSource`) while `.signedIn`. Built by the route transition (pure
    /// construction); the shell's `.task` starts it, and every fetch, digest and projection then
    /// runs off the main actor.
    public private(set) var home: HomeModel?
    /// Ends the previous session after `exitSample()` or `signOut()`; owned here so it is never
    /// orphaned.
    private let teardown = TaskBox()

    public init(accountRuntime: AccountRuntime = AccountRuntime()) {
        self.accountRuntime = accountRuntime
    }

    /// Resolves the launch route. There is no account directory to consult yet (the launch
    /// bootstrapper is perf-app-runtime.md §7 step 8), so the honest destination is Welcome.
    public func bootstrap() {
        guard route == .launching else { return }
        route = .welcome
    }

    /// Welcome's (and "school not enabled"'s) "Explore with Sample Data": a root switch, never a
    /// push. Only constructs the models (no I/O), so the shell paints in the same frame.
    public func enterSample() {
        guard route == .welcome else { return }
        home = HomeModel(source: SampleSession())
        route = .sample
    }

    /// The SAMPLE DATA banner's "Exit": back to Welcome without replaying the brand moment, then
    /// the session ends (perf-app-runtime.md §4.3). The route switches first, in this call, so the
    /// shell goes away and SwiftUI cancels its tasks; then `homeTeardown` ends the model, its
    /// projector and its session off the view's lifetime: streams finish, the snapshot is released.
    public func exitSample() {
        guard route == .sample else { return }
        playsBrandMoment = false
        route = .welcome
        guard let ending = home else { return }
        home = nil
        teardown.replace(with: Task { await ending.end() })
    }

    /// Sign-in's first sync finished for `account`: a root switch to its Home shell over the
    /// account's coordinator, which releases the Welcome stack and its view models.
    public func completeSignIn(_ account: AccountKey) {
        guard route == .welcome else { return }
        home = HomeModel(source: AccountHomeSource(runtime: accountRuntime))
        route = .signedIn(account)
    }

    /// Back to Welcome (with the brand moment), in perf-app-runtime.md §4.3's order: the route
    /// (views go away), the status model, the intent bridge, then, off the view's lifetime, the
    /// Home model and the account's coordinator (`bumpEpochAndCancel()`: any run in flight is
    /// discarded, every stream finishes, the snapshot is released). The purge and the widget
    /// reload land with §7 step 10.
    public func signOut() {
        guard case .signedIn = route else { return }
        route = .welcome
        playsBrandMoment = true
        detach()
        let endingHome = home
        home = nil
        let runtime = accountRuntime
        teardown.replace(with: Task {
            await endingHome?.end()
            await runtime.end()
        })
    }

    /// Called once a `RefreshCoordinator` exists for the signed-in account: it becomes the
    /// runtime's coordinator, the intent's and the status model's. Sample data never comes
    /// through here: it must never reach the background task or the Siri "Refresh Tally" intent
    /// (ASC-14's "no network calls in sample mode" guarantee).
    public func attach(_ coordinator: RefreshCoordinator) async {
        await accountRuntime.install(coordinator)
        RefreshIntentBridge.coordinator = coordinator
        await refreshStatus.attach(to: coordinator)
    }

    /// Stops mirroring the coordinator and clears the intent's reference to it. The coordinator
    /// itself is retired by `signOut()`.
    public func detach() {
        RefreshIntentBridge.coordinator = nil
        refreshStatus.detach()
    }

    /// Tests: the pending teardown (sample exit or sign-out), awaited.
    func awaitTeardown() async {
        await teardown.value()
    }
}

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
/// `refreshCoordinator` is `nil` today: there is no signed-in account yet (the account session
/// lands with sign-in's first sync, perf-app-runtime.md §7 step 9). That is the real, honest state
/// of the app right now, not a stub. `attach(_:)`/`detach()` are the one place the "Refresh Tally"
/// intent's `RefreshIntentBridge` is set and cleared.
@MainActor
@Observable
public final class AppModel {
    public private(set) var route: RootRoute = .launching
    /// Whether the next Welcome appearance plays the brand moment. ux-ui.md §3.2 stage 1: it plays
    /// on "first run and after sign-out only", so it is `true` at launch and after `signOut()`,
    /// and `false` once the student has left Welcome for sample data and comes back.
    public private(set) var playsBrandMoment = true
    public private(set) var refreshCoordinator: RefreshCoordinator?
    public let refreshStatus = RefreshStatusModel()

    public init() {}

    /// Resolves the launch route. There is no account directory to consult yet (the launch
    /// bootstrapper is perf-app-runtime.md §7 step 8), so the honest destination is Welcome.
    public func bootstrap() {
        guard route == .launching else { return }
        route = .welcome
    }

    /// Welcome's (and "school not enabled"'s) "Explore with Sample Data": a root switch, never a push.
    public func enterSample() {
        guard route == .welcome else { return }
        route = .sample
    }

    /// The SAMPLE DATA banner's "Exit": back to Welcome, without replaying the brand moment.
    public func exitSample() {
        guard route == .sample else { return }
        playsBrandMoment = false
        route = .welcome
    }

    /// Sign-in's first sync finished for `account`: a root switch to its Home shell, which releases
    /// the Welcome stack and its view models.
    public func completeSignIn(_ account: AccountKey) {
        guard route == .welcome else { return }
        route = .signedIn(account)
    }

    /// Back to Welcome (with the brand moment), no longer attached to the account's coordinator.
    /// The rest of the sign-out order (purge, epoch bump, widget reload) is perf-app-runtime.md
    /// §4.3 and lands with §7 step 10.
    public func signOut() {
        guard case .signedIn = route else { return }
        route = .welcome
        playsBrandMoment = true
        detach()
    }

    /// Called once a `RefreshCoordinator` exists for the signed-in account. Sample data never comes
    /// through here: it must never reach the background task or the Siri "Refresh Tally" intent
    /// (ASC-14's "no network calls in sample mode" guarantee).
    public func attach(_ coordinator: RefreshCoordinator) async {
        refreshCoordinator = coordinator
        RefreshIntentBridge.coordinator = coordinator
        await refreshStatus.attach(to: coordinator)
    }

    public func detach() {
        refreshCoordinator = nil
        RefreshIntentBridge.coordinator = nil
        refreshStatus.detach()
    }
}

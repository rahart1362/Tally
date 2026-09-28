import Foundation

/// Every place the onboarding flow can lead *inside* the welcome `NavigationStack`: plain pushed
/// pages only. Associated values are primitives (never the full `InstitutionMatch`/
/// `ClientRegistration`), so the route stays trivially `Hashable` without asking those
/// `TallyCanvasAPI` types to conform.
///
/// ASC-14's "Explore with Sample Data" is deliberately **not** a case here: sample data is a root
/// route (`RootRoute.sample`), because the Home shell is a `TabView` and a pushed `TabView` does
/// not render (see `HomeShellView`).
nonisolated enum WelcomeRoute: Hashable, Sendable {
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

/// The onboarding stack's path edits, as pure functions (plan 06 A8; crash-safety-2.md §8 A4/A5).
/// `path.removeLast()` traps on an empty path, which a repeated tap during a pop animation or a
/// stale closure can reach. Each edit applies only while the page that asks for it is on top, so a
/// stale closure can neither trap nor pop some other page.
nonisolated enum WelcomePath {
    /// Pops `page` when it is the top page; otherwise (an empty path, or a closure from a page that
    /// is no longer on top) does nothing.
    static func pop(_ page: WelcomeRoute, from path: inout [WelcomeRoute]) {
        guard !path.isEmpty else { return } // MUTATION MA8a: pops whatever page is on top
        path.removeLast()
    }

    /// Replaces `page`, when it is the top page, with a fresh copy of itself (a retry); otherwise
    /// does nothing.
    static func restart(_ page: WelcomeRoute, in path: inout [WelcomeRoute]) {
        guard !path.isEmpty, path.last == page else { return }
        path.removeLast()
        path.append(page)
    }
}

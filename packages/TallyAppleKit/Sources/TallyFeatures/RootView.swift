import SwiftUI
import TallyDesignSystem

/// Where the welcome screen can lead that stays *inside* its own `NavigationStack` (a plain
/// pushed page). ASC-14's "Explore with Sample Data" is deliberately not a case here — see
/// `RootView`'s doc comment for why.
enum WelcomeRoute: Hashable {
    case findSchool
}

/// The app's single root view (architecture.md §3.1: the `Tally` target is
/// "composition root only"; everything else, including navigation, lives
/// here in `TallyFeatures`). Composed as `NavigationStack` + the welcome
/// screen + stub destinations, per the iOS 26 navigation shell in
/// ux-ui.md §3.4.
///
/// ASC-14 "Explore with Sample Data" is a **sibling root**, switched on a plain `Bool`, not a
/// `navigationDestination` push. `SampleDataRootView` contains `TabShellView`, and `TabShellView`
/// is a `TabView`: CI (runs 36348080137 → 36353526769, five separate configurations bisected one
/// variable at a time — the tap mechanism, the button style, the route/push machinery, the data
/// layer both raw and rebased, and finally the Dashboard tab's own content in isolation) proved
/// that a `TabView` does not reliably render when it is the content of a page *pushed* onto a
/// `NavigationStack`: every configuration with a pushed `TabView` silently failed to appear
/// (XCUITest saw no crash and no navigation — the app simply stayed on Welcome), while the exact
/// same content shown as this stack's *root* (see below) works. Nesting a `TabView` inside a
/// pushed destination is a known-unreliable SwiftUI pattern; a `TabView` should be a screen's own
/// root, never content pushed onto another `NavigationStack`.
public struct RootView: View {
    @State private var path: [WelcomeRoute] = []
    @State private var isExploringSampleData = false

    public init() {}

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
                    switch route {
                    case .findSchool:
                        FindSchoolStub()
                    }
                }
            }
        }
    }
}

import SwiftUI
import TallyDesignSystem

/// The two places the welcome screen can lead. Both are stubs today — no
/// networking, no fixtures, no fake data — because the school-search and
/// sample-data flows are separate, later work packages (implementation
/// brief: "Navigation stubs only, with no fake data").
enum WelcomeRoute: Hashable {
    case findSchool
    case sampleData
}

/// The app's single root view (architecture.md §3.1: the `Tally` target is
/// "composition root only"; everything else, including navigation, lives
/// here in `TallyFeatures`). Composed as `NavigationStack` + the welcome
/// screen + stub destinations, per the iOS 26 navigation shell in
/// ux-ui.md §3.4.
public struct RootView: View {
    @State private var path: [WelcomeRoute] = []

    public init() {}

    public var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(
                onFindSchool: { path.append(.findSchool) },
                onExploreSampleData: { path.append(.sampleData) }
            )
            .navigationDestination(for: WelcomeRoute.self) { route in
                switch route {
                case .findSchool:
                    FindSchoolStub()
                case .sampleData:
                    SampleDataStub()
                }
            }
        }
    }
}

import SwiftUI
import TallyCanvasAPI
import TallyDesignSystem

/// Every place the onboarding flow can lead (implementation brief: "Navigation
/// stubs only, with no fake data" grew into UX-WP-08/09 as those work
/// packages landed). Associated values are primitives (never the full
/// `InstitutionMatch`/`ClientRegistration`), so the route stays trivially
/// `Hashable` without asking those `TallyCanvasAPI` types to conform.
enum WelcomeRoute: Hashable {
    case findSchool
    case sampleData
    /// A search result or typed address had no `ClientRegistry` entry
    /// (UX-WP-08; ux-ui.md §3.2.1's "not enabled" row).
    case schoolNotEnabled(school: String)
    /// A chosen school is enabled: on to the sign-in hand-off (UX-WP-09).
    case signIn(host: String, clientID: String, schoolDisplayName: String)
}

/// The app's single root view (architecture.md §3.1: the `Tally` target is
/// "composition root only"; everything else, including navigation, lives
/// here in `TallyFeatures`). Composed as `NavigationStack` + the welcome
/// screen + the onboarding destinations, per the iOS 26 navigation shell in
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
                case .sampleData:
                    SampleDataStub()
                case .schoolNotEnabled(let school):
                    SchoolNotEnabledView(school: school, onExploreSampleData: { path = [.sampleData] })
                case .signIn(let host, let clientID, let schoolDisplayName):
                    // UX-WP-09 replaces this with the real sign-in hand-off screen.
                    SignInHandoffStub(host: host, clientID: clientID, schoolDisplayName: schoolDisplayName)
                }
            }
        }
    }
}

/// Placeholder destination for an enabled school, ahead of UX-WP-09's real
/// hand-off screen — the same "obvious no-op, not fake data" pattern
/// `FindSchoolStub`/`SampleDataStub` used before their own work packages
/// landed.
private struct SignInHandoffStub: View {
    let host: String
    let clientID: String
    let schoolDisplayName: String

    var body: some View {
        ContentUnavailableView(
            "Sign in to \(schoolDisplayName)",
            systemImage: "person.crop.circle.badge.checkmark",
            description: Text("The sign-in hand-off lands in a later milestone. (\(host))")
        )
        .background(TallyColor.bgCanvas)
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.large)
    }
}

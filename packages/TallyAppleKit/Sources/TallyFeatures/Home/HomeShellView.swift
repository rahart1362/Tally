import Combine
import UIKit
import SwiftUI
import TallyDesignSystem
import TallyDomain

/// UX-WP-05: the Home shell. Five tabs — Dashboard, Courses, Calendar, To-Do,
/// **Insights** (never "More", ux-ui.md §3.4/app-store-compliance.md R5) — using the plain
/// system tab bar (`Tab(_:systemImage:)`, iOS 18 API) with no `UITabBarAppearance` overrides, so
/// Liquid Glass renders the way the platform gives it "automatically" (ux-ui.md §3.4). Settings
/// is a sheet from the toolbar, never pushed, never nested (ux-ui.md §3.4).
///
/// **A root only.** This view is the app's root `TabView`, each tab owning its own
/// `NavigationStack`, so it is built only by `RootView` for `RootRoute.sample` and
/// `.signedIn` (perf-app-runtime.md §3 item 2). A pushed `TabView` does not render (2d3131f's
/// bisect), and CI's hygiene job fails if any other shipping file constructs this type.
///
/// It renders `HomeModel`'s precomputed rows only (perf-app-runtime.md §7 step 6): the model's
/// projector sorts, filters and formats off the main actor. It also keeps the projection current:
/// it re-projects when `validUntil` passes, when the scene becomes active late, and when the day,
/// the clock or the time zone changes.
public struct HomeShellView: View {
    let model: HomeModel
    /// A persistent banner slotted above the tab content (ASC-14's SAMPLE DATA banner); `nil`
    /// outside sample mode.
    let banner: AnyView?

    @Environment(\.scenePhase) private var scenePhase
    /// `RootView` puts it here for the sample and signed-in routes; Settings' account actions use it.
    @Environment(AppModel.self) private var appModel: AppModel?
    @State private var isSettingsPresented = false

    public init(model: HomeModel, banner: AnyView? = nil) {
        self.model = model
        self.banner = banner
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let banner {
                banner
            }

            TabView {
                Tab("Dashboard", systemImage: "house") {
                    NavigationStack {
                        DashboardView()
                            .toolbar { settingsToolbarItem }
                    }
                }
                // M3-A (E05a-e, UX-WP-14…20): each tab's root screen, over `model`'s projections.
                Tab("Courses", systemImage: "books.vertical") {
                    NavigationStack {
                        CoursesScreen()
                            .modifier(FreshnessSubtitle())
                            .toolbar { settingsToolbarItem }
                    }
                }
                Tab("Calendar", systemImage: "calendar") {
                    NavigationStack {
                        CalendarScreen()
                            .modifier(FreshnessSubtitle())
                            .toolbar { settingsToolbarItem }
                    }
                }
                Tab("To-Do", systemImage: "checklist") {
                    NavigationStack {
                        ToDoScreen()
                            .modifier(FreshnessSubtitle())
                            .toolbar { settingsToolbarItem }
                    }
                }
                // ux-ui.md §3.4: the To-Do badge counts missing work only (HIG: critical information).
                .badge(model.toDoScreen.missingCount)
                Tab("Insights", systemImage: "chart.xyaxis.line") {
                    NavigationStack {
                        InsightsScreen()
                            .modifier(FreshnessSubtitle())
                            .toolbar { settingsToolbarItem }
                    }
                }
            }
            // A dynamic colour (ux-ui.md §3.4: "never navy on dark"); minimised-on-scroll is the
            // system default for a 2-tab bar but not requested here, so no `.tabViewStyle` override.
            .tint(TallyColor.accent)
        }
        .environment(model)
        .sheet(isPresented: $isSettingsPresented) {
            // M3-A (UX-WP-20): the sheet's content gets the Home model and the app model explicitly.
            SettingsView()
                .environment(model)
                .environment(appModel)
        }
        .task { await model.start() }
        .task(id: model.validUntil) { await model.reprojectWhenStale() }
        .task(id: scenePhase) {
            if scenePhase == .active { await model.projectIfStale() }
        }
        // Delivered on the main run loop: these notifications may be posted from any thread, and
        // an `onReceive` action formed in `body` is main-actor isolated (SE-0423 would trap).
        .onReceive(Self.clockChanges) { _ in model.clockDidChange() }
    }

    /// The day, the wall clock or the time zone changed: date-relative rows may be wrong.
    private static var clockChanges: some Publisher<Notification, Never> {
        let center = NotificationCenter.default
        return Publishers.MergeMany(
            center.publisher(for: .NSCalendarDayChanged),
            center.publisher(for: .NSSystemTimeZoneDidChange),
            center.publisher(for: UIApplication.significantTimeChangeNotification)
        )
        .receive(on: RunLoop.main)
    }

    @ToolbarContentBuilder
    private var settingsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                isSettingsPresented = true
            } label: {
                Image(systemName: "person.crop.circle")
            }
            .accessibilityLabel("Settings")
        }
    }
}

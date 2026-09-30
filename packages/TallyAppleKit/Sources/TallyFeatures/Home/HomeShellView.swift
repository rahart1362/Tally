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
///
/// **Only the selected tab is built** (PERF-L, `Launch.HomeRender`): the launch builds the
/// Dashboard's stack alone, and each other tab's stack is built the first time it is selected.
/// A built tab stays built, so it keeps its navigation path and scroll position when the student
/// switches away and back. On iOS 26.2 and 26.5 `TabView` already defers an unselected tab's
/// content until it is selected (CI mutation MH1, run 36701247111: with every tab marked built,
/// only the Dashboard's content was evaluated at launch), so this saves no launch work there; it
/// makes the behaviour explicit instead of relying on `TabView`'s.
public struct HomeShellView: View {
    let model: HomeModel
    /// A persistent banner slotted above the tab content (ASC-14's SAMPLE DATA banner); `nil`
    /// outside sample mode.
    let banner: AnyView?

    @Environment(\.scenePhase) private var scenePhase
    /// `RootView` puts it here for the sample and signed-in routes; Settings' account actions use it.
    @Environment(AppModel.self) private var appModel: AppModel?
    @State private var isSettingsPresented = false
    @State private var selectedTab: HomeTab = .dashboard
    /// The tabs whose content exists: the Dashboard from the first frame, each other tab from its
    /// first selection on. Only ever grows, so a built tab's `NavigationStack` keeps its identity.
    @State private var builtTabs: Set<HomeTab> = [.dashboard]

    public init(model: HomeModel, banner: AnyView? = nil) {
        self.model = model
        self.banner = banner
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let banner {
                banner
            }

            TabView(selection: tabSelection) {
                Tab("Dashboard", systemImage: "house", value: HomeTab.dashboard) {
                    BuiltTab(.dashboard, isBuilt: builtTabs.contains(.dashboard)) {
                        NavigationStack {
                            DashboardView()
                                .toolbar { settingsToolbarItem }
                        }
                    }
                }
                // M3-A (E05a-e, UX-WP-14…20): each tab's root screen, over `model`'s projections.
                Tab("Courses", systemImage: "books.vertical", value: HomeTab.courses) {
                    BuiltTab(.courses, isBuilt: builtTabs.contains(.courses)) {
                        NavigationStack {
                            CoursesScreen()
                                .modifier(FreshnessSubtitle())
                                .toolbar { settingsToolbarItem }
                        }
                    }
                }
                Tab("Calendar", systemImage: "calendar", value: HomeTab.calendar) {
                    BuiltTab(.calendar, isBuilt: builtTabs.contains(.calendar)) {
                        NavigationStack {
                            CalendarScreen()
                                .modifier(FreshnessSubtitle())
                                .toolbar { settingsToolbarItem }
                        }
                    }
                }
                Tab("To-Do", systemImage: "checklist", value: HomeTab.toDo) {
                    BuiltTab(.toDo, isBuilt: builtTabs.contains(.toDo)) {
                        NavigationStack {
                            ToDoScreen()
                                .modifier(FreshnessSubtitle())
                                .toolbar { settingsToolbarItem }
                        }
                    }
                }
                // ux-ui.md §3.4: the To-Do badge counts missing work only (HIG: critical information).
                .badge(model.toDoScreen.missingCount)
                Tab("Insights", systemImage: "chart.xyaxis.line", value: HomeTab.insights) {
                    BuiltTab(.insights, isBuilt: builtTabs.contains(.insights)) {
                        NavigationStack {
                            InsightsScreen()
                                .modifier(FreshnessSubtitle())
                                .toolbar { settingsToolbarItem }
                        }
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

    /// The tab bar's selection. A tab is marked built in the same update that selects it, so its
    /// first frame already has its content (never the empty stand-in).
    private var tabSelection: Binding<HomeTab> {
        Binding(get: { selectedTab }, set: { tab in
            builtTabs.insert(tab)
            selectedTab = tab
        })
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

/// The Home shell's five tabs, in tab-bar order.
nonisolated enum HomeTab: String, Hashable, Sendable, CaseIterable {
    case dashboard, courses, calendar, toDo, insights
}

/// One tab's content, built only once `isBuilt` (the tab has been selected at least once); an empty
/// stand-in until then. In DEBUG it counts its own body evaluations under `HomeTab.<name>`, so a
/// hosted test can see which tabs the shell actually built (`HomeShellTabTests`).
private struct BuiltTab<Content: View>: View {
    let tab: HomeTab
    let isBuilt: Bool
    let content: () -> Content
    #if DEBUG
    @Environment(\.bodyEvaluationCounter) private var bodyCounter
    #endif

    init(_ tab: HomeTab, isBuilt: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.tab = tab
        self.isBuilt = isBuilt
        self.content = content
    }

    var body: some View {
        if isBuilt {
            #if DEBUG
            let _ = bodyCounter?.record("HomeTab.\(tab.rawValue)")
            #endif
            content()
        } else {
            Color.clear
        }
    }
}

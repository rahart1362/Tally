import Combine
import UIKit
import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

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
    /// FAM-09: the switcher shows initials only from AX1 up; read here, where the size is not clamped.
    @Environment(\.dynamicTypeSize) private var typeSize
    /// `RootView` puts it here for the sample and signed-in routes; Settings' account actions use it.
    @Environment(AppModel.self) private var appModel: AppModel?
    @State private var isSettingsPresented = false
    /// FAM-09 (M3-E2): the switcher's "Add a student…" opens Settings at its add-student sheet.
    @State private var settingsAddsStudent = false
    @State private var selectedTab: HomeTab = .dashboard
    /// The tabs whose content exists: the Dashboard from the first frame, each other tab from its
    /// first selection on. Only ever grows, so a built tab's `NavigationStack` keeps its identity.
    @State private var builtTabs: Set<HomeTab> = [.dashboard]

    public init(model: HomeModel, banner: AnyView? = nil) {
        self.model = model
        self.banner = banner
    }

    /// FAM-09 (M3-E2): parent mode's family, when there is one (sample mode's parent view today).
    private var family: FamilyModel? { appModel?.family }

    /// The Home every tab shows: in parent mode the active student's (each student has their own
    /// model and cache), otherwise the shell's own.
    private var home: HomeModel { family?.activeHome ?? model }

    public var body: some View {
        VStack(spacing: 0) {
            if let banner {
                banner
            }

            // FAM-09: parent mode with no student left: §7.6's parent empty state replaces the tabs.
            if let family, family.students.isEmpty {
                NavigationStack {
                    TallyUnavailableView(Text(L10n.FamilyUI.linkedStudentsHeader()), systemImage: "person.2",
                                         description: Text(L10n.FamilyUI.parentNoStudents())) {
                        Button(String(localized: L10n.FamilyUI.addStudent())) { openSettings(addingStudent: true) }
                            .accessibilityIdentifier("family.emptyAdd")
                    }
                    // ux-fp2 D20: centred when it fits, scrolling when it does not (AX5), with the
                    // D01 chrome, since it can now scroll under the bar.
                    .tallyCenteredScrolling()
                    .tallyScreenChrome()
                    .toolbar { settingsToolbarItem }
                }
            } else {
                // The lint (`scripts/ci/check_localizable_literals.py`) does not yet know the iOS 18
                // `Tab(_:systemImage:value:)` initializer (its `UI_CALLEES` set predates it), so these
                // five were not findings; moved anyway; they are genuinely user-facing tab bar labels,
                // the same practice L10N-03a's report documents for other lint gaps (flagged for the PMO
                // in the hand-off report, §3.8).
                TabView(selection: tabSelection) {
                    Tab(String(localized: L10n.Home.tabDashboard()), systemImage: "house", value: HomeTab.dashboard) {
                        BuiltTab(.dashboard, isBuilt: builtTabs.contains(.dashboard)) {
                            NavigationStack {
                                DashboardView()
                                    .toolbar { settingsToolbarItem }
                                    .modifier(ParentModeInlineTitle(isOn: family != nil))
                            }
                        }
                    }
                    // M3-A (E05a-e, UX-WP-14…20): each tab's root screen, over `model`'s projections.
                    Tab(String(localized: L10n.Home.tabCourses()), systemImage: "books.vertical", value: HomeTab.courses) {
                        BuiltTab(.courses, isBuilt: builtTabs.contains(.courses)) {
                            NavigationStack {
                                CoursesScreen()
                                    .modifier(FreshnessSubtitle())
                                    .modifier(SubscriptionLock()) // PAY-06 (d): the locked card in its place
                                    // D25: the locked card replaces the whole screen, including its
                                    // own `.navigationTitle` call, so the tab showed none. Set
                                    // outside the lock: unlocked, the screen's own title (same
                                    // text) still wins; locked, this is the only one left.
                                    .navigationTitle(String(localized: L10n.Courses.navigationTitle()))
                                    .toolbar { settingsToolbarItem }
                                    .modifier(ParentModeInlineTitle(isOn: family != nil))
                            }
                        }
                    }
                    Tab(String(localized: L10n.Home.tabCalendar()), systemImage: "calendar", value: HomeTab.calendar) {
                        BuiltTab(.calendar, isBuilt: builtTabs.contains(.calendar)) {
                            NavigationStack {
                                CalendarScreen()
                                    .modifier(FreshnessSubtitle())
                                    .modifier(SubscriptionLock()) // PAY-06 (d): the locked card in its place
                                    // D25: see the Courses tab above. Calendar's own title is the
                                    // current month, which needs its model's data; the generic tab
                                    // title is what showed before that data existed anyway.
                                    .navigationTitle(Text(L10n.Calendar.tabTitle()))
                                    .toolbar { settingsToolbarItem }
                                    .modifier(ParentModeInlineTitle(isOn: family != nil))
                            }
                        }
                    }
                    Tab(String(localized: L10n.Home.tabToDo()), systemImage: "checklist", value: HomeTab.toDo) {
                        BuiltTab(.toDo, isBuilt: builtTabs.contains(.toDo)) {
                            NavigationStack {
                                ToDoScreen()
                                    .modifier(FreshnessSubtitle())
                                    .modifier(SubscriptionLock()) // PAY-06 (d): the locked card in its place
                                    // D25: see the Courses tab above.
                                    .navigationTitle(String(localized: L10n.ToDo.navigationTitle()))
                                    .toolbar { settingsToolbarItem }
                                    .modifier(ParentModeInlineTitle(isOn: family != nil))
                            }
                        }
                    }
                    // ux-ui.md §3.4: the To-Do badge counts missing work only (HIG: critical information).
                    .badge(home.toDoScreen.missingCount)
                    Tab(String(localized: L10n.Home.tabInsights()), systemImage: "chart.xyaxis.line", value: HomeTab.insights) {
                        BuiltTab(.insights, isBuilt: builtTabs.contains(.insights)) {
                            NavigationStack {
                                InsightsScreen()
                                    .modifier(FreshnessSubtitle())
                                    .modifier(SubscriptionLock()) // PAY-06 (d): the locked card in its place
                                    // D25: see the Courses tab above.
                                    .navigationTitle(String(localized: L10n.Insights.navigationTitle()))
                                    .toolbar { settingsToolbarItem }
                                    .modifier(ParentModeInlineTitle(isOn: family != nil))
                            }
                        }
                    }
                }
                // A dynamic colour (ux-ui.md §3.4: "never navy on dark"); minimised-on-scroll is the
                // system default for a 2-tab bar but not requested here, so no `.tabViewStyle` override.
                .tint(TallyColor.accent)
                // FAM-09: each student's tabs are their own (a pushed course of one student never shows
                // under another); the selected tab stays (it is this view's state). An opacity-only
                // cross-fade, the same with Reduce Motion on.
                .id(family?.activeSubject)
                .transition(.opacity)
            }
        }
        // R2 (ux-fp1 round 2): the banner's own D29 fix keeps its fill off the status bar
        // (`SampleDataBanner.swift`'s `ignoresSafeAreaEdges: []`), so whatever sits behind this
        // VStack shows through there instead — with nothing painted here, that was the system's
        // plain white/black, not the Tally canvas every other status bar on the app shows. This
        // reaches behind both the banner and the tabs' own content (sample mode's parent-empty
        // state included), painting only the strip neither of them already covers opaquely.
        .background(TallyColor.bgCanvas, ignoresSafeAreaEdges: .top)
        .animation(.easeInOut(duration: Self.studentSwitchFade), value: family?.activeSubject)
        .environment(home)
        // The Home's one sheet: Settings, or M3-B2's paywall (`AppModel.paywall`). One presenter: with
        // two chained `.sheet` modifiers here, the subscription changing under Settings closed it (run
        // 36976774341).
        .sheet(item: presentedSheet) { sheet in
            switch sheet {
            case .settings:
                // M3-A (UX-WP-20): the sheet's content gets the Home model and the app model explicitly.
                SettingsView(opensAddStudent: settingsAddsStudent)
                    .environment(home)
                    .environment(appModel)
            case .paywall(let request):
                if let appModel {
                    PaywallView(model: PaywallModel(trigger: request.trigger, school: home.dashboard.hero.school,
                                                    subscription: appModel.subscription, storefront: appModel.storefront))
                }
            }
        }
        // FAM-09: a student shown for the first time starts their own Home (`start()` runs once).
        .task(id: ObjectIdentifier(home)) { await home.start() }
        .task(id: home.validUntil) { await home.reprojectWhenStale() }
        .task(id: scenePhase) {
            if scenePhase == .active { await home.projectIfStale() }
        }
        // Delivered on the main run loop: these notifications may be posted from any thread, and
        // an `onReceive` action formed in `body` is main-actor isolated (SE-0423 would trap).
        .onReceive(Self.clockChanges) { _ in home.clockDidChange() }
        // PAY-06 (M3-B2): the paywall, once, after the first sync rendered the Dashboard.
        .modifier(FirstSyncPaywallTrigger(home: home))
        // FAM-10 (§7.6 "Link removed"): told once, after the student's data went.
        .alert(String(localized: L10n.FamilyUI.linkRemovedTitle()), isPresented: removedNoticeShown, presenting: family?.removedNotice) { _ in
            Button(String(localized: L10n.FamilyUI.ok())) { family?.removedNotice = nil }
        } message: { student in
            Text(L10n.FamilyUI.linkRemoved(student.firstName))
        }
    }

    /// FAM-09: how long a student switch cross-fades.
    private static let studentSwitchFade = 0.25

    private var removedNoticeShown: Binding<Bool> {
        Binding(get: { family?.removedNotice != nil }, set: { shown in
            if !shown { family?.removedNotice = nil }
        })
    }

    /// Settings, from its toolbar button or (FAM-09) the switcher's menu.
    private func openSettings(addingStudent: Bool = false) {
        settingsAddsStudent = addingStudent
        isSettingsPresented = true
    }

    /// Settings while its button asked for it; otherwise the paywall `AppModel` asked for, if any.
    private var presentedSheet: Binding<HomeSheet?> {
        Binding(get: {
            if isSettingsPresented { return .settings }
            return appModel?.paywall.map(HomeSheet.paywall)
        }, set: { sheet in
            guard sheet == nil else { return }
            if isSettingsPresented {
                isSettingsPresented = false
            } else {
                appModel?.dismissPaywall()
            }
        })
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

    /// Every tab root's toolbar: in parent mode the student-switcher (FAM-09, §7.1) at its centre, so
    /// the student is named on every tab; then Settings.
    @ToolbarContentBuilder
    private var settingsToolbarItem: some ToolbarContent {
        if let family, family.activeStudent != nil {
            ToolbarItem(placement: .principal) {
                StudentSwitcher(family: family, showsInitialsOnly: typeSize.isAccessibilitySize,
                                isAccessibilitySize: typeSize.isAccessibilitySize,
                                onManage: { openSettings() }, onAdd: { openSettings(addingStudent: true) })
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                openSettings()
            } label: {
                Image(systemName: "person.crop.circle")
            }
            .accessibilityLabel(Text(L10n.Home.settingsButton()))
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

/// FAM-09: how a principal toolbar item renders beside a large navigation title on iOS 26/27 is
/// UNVERIFIED (family-linking.md §7.1), so parent mode takes the spec's fallback: inline titles on
/// the tab roots, where the switcher stands in for the title. Outside parent mode nothing changes.
private struct ParentModeInlineTitle: ViewModifier {
    let isOn: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isOn {
            content.navigationBarTitleDisplayMode(.inline)
        } else {
            content
        }
    }
}

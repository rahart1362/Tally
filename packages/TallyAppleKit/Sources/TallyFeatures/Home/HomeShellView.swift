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
                Tab("Courses", systemImage: "books.vertical") {
                    NavigationStack {
                        CoursesListView(courses: model.courses)
                            .modifier(FreshnessSubtitle())
                            .toolbar { settingsToolbarItem }
                    }
                }
                Tab("Calendar", systemImage: "calendar") {
                    NavigationStack {
                        CalendarListView(events: model.events)
                            .modifier(FreshnessSubtitle())
                            .toolbar { settingsToolbarItem }
                    }
                }
                Tab("To-Do", systemImage: "checklist") {
                    NavigationStack {
                        ToDoListView(items: model.toDo)
                            .modifier(FreshnessSubtitle())
                            .toolbar { settingsToolbarItem }
                    }
                }
                Tab("Insights", systemImage: "chart.xyaxis.line") {
                    NavigationStack {
                        InsightsPlaceholderView(courses: model.courses)
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
            SettingsPlaceholderView()
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

/// A neutral, data-driven empty state (implementation brief / UX-WP-05: "'Coming soon' is not
/// acceptable in shipping; use a neutral 'No items' state driven by real data"). Full screens for
/// Courses, Calendar, To-Do and Insights are separate M3 work packages (E05a-e,
/// UX-WP-14…20); these are minimal, honest, real-data list views over precomputed rows.
struct CoursesListView: View {
    let courses: [HomeProjection.CourseRow]

    var body: some View {
        Group {
            if courses.isEmpty {
                ContentUnavailableView("No courses yet", systemImage: "books.vertical",
                                       description: Text("Your courses will appear here once you're signed in."))
            } else {
                List(courses) { course in
                    VStack(alignment: .leading, spacing: TallySpacing.xs) {
                        Text(course.code).font(TallyTypography.cardTitle)
                        Text(course.name).font(TallyTypography.footnote).foregroundStyle(TallyColor.textSecondary)
                        if let percent = course.percent {
                            Text(percent.formatted(.number.precision(.fractionLength(1))) + "%")
                                .font(TallyTypography.subheadline).foregroundStyle(TallyColor.textSecondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Courses")
    }
}

struct CalendarListView: View {
    let events: [HomeProjection.EventRow]

    var body: some View {
        Group {
            if events.isEmpty {
                ContentUnavailableView("No events yet", systemImage: "calendar",
                                       description: Text("Your class schedule and exams will appear here."))
            } else {
                List(events) { event in
                    VStack(alignment: .leading, spacing: TallySpacing.xs) {
                        Text(event.title).font(TallyTypography.cardTitle)
                        Text(event.startAt.formatted(date: .abbreviated, time: .shortened))
                            .font(TallyTypography.footnote).foregroundStyle(TallyColor.textSecondary)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Calendar")
    }
}

struct ToDoListView: View {
    let items: [HomeProjection.ToDoRow]

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView("No items", systemImage: "checklist",
                                       description: Text("Assignments and to-dos will appear here."))
            } else {
                List(items) { item in
                    VStack(alignment: .leading, spacing: TallySpacing.xs) {
                        Text(item.title).font(TallyTypography.cardTitle)
                        if let due = item.dueAt {
                            Text("Due \(due.formatted(date: .abbreviated, time: .shortened))")
                                .font(TallyTypography.footnote).foregroundStyle(TallyColor.textSecondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("To-Do")
    }
}

/// UX-WP-19 (Insights, renamed from "More") is a separate M3 work package; this is the minimal,
/// honest stand-in the tab shell needs today.
struct InsightsPlaceholderView: View {
    let courses: [HomeProjection.CourseRow]

    var body: some View {
        Group {
            if courses.isEmpty {
                ContentUnavailableView("No insights yet", systemImage: "chart.xyaxis.line",
                                       description: Text("Trends and course health will appear here."))
            } else {
                List(courses) { course in
                    HStack {
                        Text(course.code).font(TallyTypography.cardTitle)
                        Spacer()
                        if let grade = course.letterGrade {
                            Text(grade).font(TallyTypography.subheadline).foregroundStyle(TallyColor.textSecondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Insights")
    }
}

/// UX-WP-05: "Settings is presented as a sheet from the toolbar." The full Settings `Form`
/// (Sign Out & Erase, etc.) is UX-WP-20/M3 scope; this is the honest placeholder until then.
struct SettingsPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Settings", systemImage: "gearshape",
                                   description: Text("Account and notification settings will appear here."))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

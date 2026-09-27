import SwiftUI
import TallyDesignSystem
import TallyDomain

/// UX-WP-05: the main navigation shell. Five tabs — Dashboard, Courses, Calendar, To-Do,
/// **Insights** (never "More", ux-ui.md §3.4/app-store-compliance.md R5) — using the plain
/// system tab bar (`Tab(_:systemImage:)`, iOS 18 API) with no `UITabBarAppearance` overrides, so
/// Liquid Glass renders the way the platform gives it "automatically" (ux-ui.md §3.4). Settings
/// is a sheet from the toolbar, never pushed, never nested (ux-ui.md §3.4).
///
/// Takes its data purely as parameters (a `CanvasSnapshot?` plus the freshness/refresh hooks)
/// rather than reaching for a global — this is the one view both `SampleDataRootView` (ASC-14)
/// and, later, a signed-in session can present, over whatever data source each has.
public struct TabShellView: View {
    let snapshot: CanvasSnapshot?
    let digest: ChangeDigest?
    let digestAsOf: Date?
    let freshness: FreshnessState
    let onRefresh: () async -> Void
    let studentDisplayName: String?
    /// A persistent banner slotted above the tab content (ASC-14's SAMPLE DATA banner); `nil`
    /// outside sample mode.
    let banner: AnyView?

    @State private var isSettingsPresented = false

    public init(
        snapshot: CanvasSnapshot?, digest: ChangeDigest?, digestAsOf: Date?, freshness: FreshnessState,
        studentDisplayName: String? = nil, banner: AnyView? = nil, onRefresh: @escaping () async -> Void
    ) {
        self.snapshot = snapshot
        self.digest = digest
        self.digestAsOf = digestAsOf
        self.freshness = freshness
        self.studentDisplayName = studentDisplayName
        self.banner = banner
        self.onRefresh = onRefresh
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let banner {
                banner
            }

            TabView {
                Tab("Dashboard", systemImage: "house") {
                    NavigationStack {
                        DashboardView(snapshot: snapshot, digest: digest, digestAsOf: digestAsOf,
                                     freshness: freshness, studentDisplayName: studentDisplayName, onRefresh: onRefresh)
                            .toolbar { settingsToolbarItem }
                    }
                }
                Tab("Courses", systemImage: "books.vertical") {
                    NavigationStack {
                        CoursesListView(courses: snapshot?.courses ?? [])
                            .navigationSubtitle(freshnessSubtitle)
                            .toolbar { settingsToolbarItem }
                    }
                }
                Tab("Calendar", systemImage: "calendar") {
                    NavigationStack {
                        CalendarListView(events: snapshot?.events ?? [])
                            .navigationSubtitle(freshnessSubtitle)
                            .toolbar { settingsToolbarItem }
                    }
                }
                Tab("To-Do", systemImage: "checklist") {
                    NavigationStack {
                        ToDoListView(planner: snapshot?.planner ?? [])
                            .navigationSubtitle(freshnessSubtitle)
                            .toolbar { settingsToolbarItem }
                    }
                }
                Tab("Insights", systemImage: "chart.xyaxis.line") {
                    NavigationStack {
                        InsightsPlaceholderView(courses: snapshot?.courses ?? [])
                            .navigationSubtitle(freshnessSubtitle)
                            .toolbar { settingsToolbarItem }
                    }
                }
            }
            // A dynamic colour (ux-ui.md §3.4: "never navy on dark"); minimised-on-scroll is the
            // system default for a 2-tab bar but not requested here, so no `.tabViewStyle` override.
            .tint(TallyColor.accent)
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsPlaceholderView()
        }
    }

    private var freshnessSubtitle: String {
        FreshnessPresenter.present(freshness, now: Date()).shortText
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
/// UX-WP-14…20); these are minimal, honest, real-data list views, not placeholders with fake rows.
struct CoursesListView: View {
    let courses: [Course]

    var body: some View {
        Group {
            if courses.isEmpty {
                ContentUnavailableView("No courses yet", systemImage: "books.vertical",
                                       description: Text("Your courses will appear here once you're signed in."))
            } else {
                List(courses) { course in
                    VStack(alignment: .leading, spacing: TallySpacing.xs) {
                        Text(course.courseCode).font(TallyTypography.cardTitle)
                        Text(course.name).font(TallyTypography.footnote).foregroundStyle(TallyColor.textSecondary)
                        if course.gradeVisibility == .visible, let percent = course.scores?.currentScore {
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
    let events: [CalendarEvent]

    var body: some View {
        Group {
            if events.isEmpty {
                ContentUnavailableView("No events yet", systemImage: "calendar",
                                       description: Text("Your class schedule and exams will appear here."))
            } else {
                List(events.sorted { $0.startAt < $1.startAt }) { event in
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
    let planner: [PlannerItem]

    var body: some View {
        Group {
            if planner.isEmpty {
                ContentUnavailableView("No items", systemImage: "checklist",
                                       description: Text("Assignments and to-dos will appear here."))
            } else {
                List(planner.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }) { item in
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
    let courses: [Course]

    var body: some View {
        Group {
            if courses.isEmpty {
                ContentUnavailableView("No insights yet", systemImage: "chart.xyaxis.line",
                                       description: Text("Trends and course health will appear here."))
            } else {
                List(courses) { course in
                    HStack {
                        Text(course.courseCode).font(TallyTypography.cardTitle)
                        Spacer()
                        if course.gradeVisibility == .visible, let grade = course.scores?.currentGrade {
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

import Foundation
import TallyDomain

/// Builds the Home shell's `HomeProjection` off the main actor (perf-app-runtime.md §2.1, §7 step
/// 6). An actor holding the **one** UI reference to the current snapshot: `install` swaps it in,
/// `project(now:)` builds every row and the dashboard from it, `end()` releases it.
///
/// The dashboard comes from `TallyDomain.DashboardBuilder` (about 70 ms at stress scale in
/// Release, about 140 ms estimated on an A13), which must never run on the main actor. Since plan
/// 08 L10N-02 it holds values, not English (the "Next up" reasons, the "Needs attention" rows and
/// the change chip), which the Dashboard's rows phrase through `TallyStrings.DashboardText` in the
/// student's language and locale; the fixed `HH:mm`/`yyyy-MM-dd` text this projector used to
/// re-render is gone from TallyDomain.
public actor HomeProjector {
    private let calendar: Calendar
    private let locale: Locale
    private var installed: HomeUpdate?
    /// How many projections this projector has built (tests: "recomputes exactly once").
    private(set) var projectionCount = 0
    /// The snapshot being projected (tests: the signed-in Home projects the coordinator's
    /// committed value itself).
    var installedSnapshot: CanvasSnapshot? { installed?.snapshot }

    public init(calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent) {
        self.calendar = calendar
        self.locale = locale
    }

    /// Holds `update`'s snapshot, replacing (and so releasing) the previous one.
    public func install(_ update: HomeUpdate) {
        installed = update
    }

    /// The projection of the installed snapshot at `now`, or `nil` when there is no snapshot yet.
    public func project(now: Date) -> HomeProjection? {
        guard let update = installed, let snapshot = update.snapshot else { return nil }
        projectionCount += 1
        let raw = TallyDomain.DashboardBuilder.build(from: snapshot, digest: update.digest, digestAsOf: update.digestAsOf, now: now)
        let dashboard = Self.withUniqueAttention(raw)
        return HomeProjection(
            generation: update.generation,
            dashboard: dashboard,
            studentDisplayName: snapshot.profile.shortName ?? snapshot.profile.name,
            greeting: Self.greeting(at: now, calendar: calendar),
            courses: snapshot.courses.map(Self.courseRow),
            events: snapshot.events
                .sorted { $0.startAt < $1.startAt }
                .map { HomeProjection.EventRow(id: $0.id, title: $0.title, startAt: $0.startAt) },
            toDo: snapshot.planner
                .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
                .map { HomeProjection.ToDoRow(id: $0.id, title: $0.title, dueAt: $0.dueAt) },
            validUntil: Self.validUntil(snapshot: snapshot, now: now, calendar: calendar),
            // M3-A: every screen's rows, in the student's locale, off the main actor.
            screens: ScreenProjections.build(
                from: snapshot, formatter: ScreenFormatter(now: now, calendar: calendar, locale: locale)))
    }

    /// Releases the snapshot (sessions are exclusive: sample exit, sign-out).
    public func end() {
        installed = nil
    }

    // MARK: - Pure pieces (nonisolated: unit-tested directly)

    /// `ForEach` needs unique IDs, but `AlertEngine.missingAlert` raises one `.missingClosed` per
    /// assignment, so every closed-missing item in a course shares one dedupe key
    /// (perf-app-runtime.md §3 item 5). Keeps the first (highest-ranked) item for each key.
    nonisolated static func withUniqueAttention(_ projection: DashboardProjection) -> DashboardProjection {
        var seen = Set<String>()
        let unique = projection.needsAttention.filter { seen.insert($0.id).inserted }
        guard unique.count != projection.needsAttention.count else { return projection }
        return DashboardProjection(hero: projection.hero, nextUp: projection.nextUp, needsAttention: unique,
                                   dueSoon: projection.dueSoon, weekAhead: projection.weekAhead,
                                   changeDigestSummary: projection.changeDigestSummary)
    }

    /// The same boundaries the pre-port `DashboardView` used for "Good morning/afternoon/evening".
    nonisolated static func greeting(at now: Date, calendar: Calendar) -> HomeProjection.Greeting {
        switch calendar.component(.hour, from: now) {
        case 0..<12: .morning
        case 12..<17: .afternoon
        default: .evening
        }
    }

    /// Windows, before a due date, at which some dashboard section changes on its own: the
    /// due-soon alert's severity bands, the 7-day "Due soon" list and the overload horizon.
    nonisolated static let dueWindows: [TimeInterval] = [
        0,
        InsightsConfig.dueSoonCriticalWindowHours * 3600,
        InsightsConfig.dueSoonHighWindowHours * 3600,
        InsightsConfig.dueSoonMediumWindowHours * 3600,
        7 * 24 * 3600,
        InsightsConfig.overloadHorizon.timeInterval,
    ]

    /// perf-app-runtime.md §2.3: the earliest of the next due-date or lock-date crossing, the next
    /// time an item enters one of `dueWindows`, the next local midnight, the next greeting
    /// boundary, and `now + TallyConfig.dashboardMaxStaleness`.
    nonisolated static func validUntil(snapshot: CanvasSnapshot, now: Date, calendar: Calendar) -> Date {
        var earliest = now.addingTimeInterval(TallyConfig.dashboardMaxStaleness.timeInterval)
        func consider(_ date: Date?) {
            guard let date, date > now, date < earliest else { return }
            earliest = date
        }
        for hour in [0, 12, 17] {
            consider(calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: 0, second: 0),
                                       matchingPolicy: .nextTime))
        }
        func considerDue(_ due: Date?) {
            guard let due else { return }
            for window in dueWindows { consider(due.addingTimeInterval(-window)) }
        }
        for groups in snapshot.groups.values {
            for group in groups {
                for assignment in group.assignments {
                    considerDue(assignment.dueAt)
                    consider(assignment.lockAt)
                }
            }
        }
        for item in snapshot.planner { considerDue(item.dueAt) }
        return earliest
    }

    nonisolated static func courseRow(_ course: Course) -> HomeProjection.CourseRow {
        let visible = course.gradeVisibility == .visible
        return HomeProjection.CourseRow(
            id: course.id, code: course.courseCode, name: course.name,
            percent: visible ? course.scores?.currentScore : nil,
            letterGrade: visible ? course.scores?.currentGrade : nil)
    }
}

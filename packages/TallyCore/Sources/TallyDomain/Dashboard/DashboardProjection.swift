import Foundation

/// PERF-02 (docs/pmo/05-perf-crash-charter.md): a faithful port of app-core's
/// `TallyFeatures.DashboardBuilder`/`DashboardViewState` (UX-WP-13, pinned review worktree
/// `packages/TallyAppleKit/Sources/TallyFeatures/Dashboard/DashboardViewState.swift` @ 6a98f4a)
/// into `TallyDomain`: pure, `Sendable`, `nonisolated`, Linux-testable, and — this is the whole
/// point — callable from a background task instead of on the main actor inside a SwiftUI
/// `body`. The root cause this fixes: `TallyFeatures` sets `.defaultIsolation(MainActor.self)`
/// package-wide, so even though the source file already opted the type out with `nonisolated`,
/// every call to it from `DashboardView.body` still ran inline on the main actor, once per body
/// evaluation. Moving the logic here doesn't change that by itself — a nonisolated pure
/// function runs on whatever thread calls it — but it lets app-core call it from a background
/// `Task` and hand `body` an already-computed value type, which a `nonisolated` function
/// sitting in an iOS-only, `MainActor`-default target could never be checked into doing safely
/// by a Linux CI gate. See this file's benchmarks in `TallyPerfTests` and the integration notes
/// in `docs/pmo/reviews/perf-core.md` for exactly how app-core should call this off-main.
///
/// Every output type, field, and rule below is unchanged from the source (same field names,
/// same rank caps, same windows) — this is a relocation, not a redesign. `GradeParityTests`-style
/// parity is enforced by `DashboardProjectionParityTests` (`same inputs -> same outputs`,
/// asserted `Equatable`) rather than trusted by inspection alone.
public nonisolated struct DashboardProjection: Equatable, Sendable {
    /// insights-at-a-glance.md §1.2 rank 3 ("Compact hero"). No sparkline/delta: both need a
    /// score *history*, which this snapshot generation does not carry (R9) — showing either
    /// would mean fabricating a trend.
    public nonisolated struct Hero: Equatable, Sendable {
        public let courseCount: Int
        /// Mean of every *visible* course's current score, `nil` when no course has one to show.
        public let overallPercent: Double?
        public let overallBand: GradeBand?

        public init(courseCount: Int, overallPercent: Double?, overallBand: GradeBand?) {
            self.courseCount = courseCount
            self.overallPercent = overallPercent
            self.overallBand = overallBand
        }
    }

    /// insights-at-a-glance.md §0/§1.2 rank 1 ("Next up").
    public nonisolated struct NextUpItem: Identifiable, Equatable, Sendable {
        public let id: CanvasID<Assignment>
        public let title: String
        public let courseCode: String
        public let dueAt: Date?
        public let band: PriorityScore.Band
        public let reason: String

        public init(id: CanvasID<Assignment>, title: String, courseCode: String, dueAt: Date?,
                    band: PriorityScore.Band, reason: String) {
            self.id = id; self.title = title; self.courseCode = courseCode; self.dueAt = dueAt
            self.band = band; self.reason = reason
        }
    }

    /// insights-at-a-glance.md §1.2 rank 2 ("Needs attention"). `subtitle` is `nil` for a bare
    /// grouped count row (e.g. "All clear" has none).
    public nonisolated struct AttentionItem: Identifiable, Equatable, Sendable {
        public let id: String
        public let severity: AlertSeverity
        public let title: String
        public let subtitle: String?

        public init(id: String, severity: AlertSeverity, title: String, subtitle: String?) {
            self.id = id; self.severity = severity; self.title = title; self.subtitle = subtitle
        }
    }

    /// insights-at-a-glance.md §1.2 rank... "Due soon" (UX review §3.7.1 item 7).
    public nonisolated struct DueItem: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let courseCode: String?
        public let dueAt: Date?

        public init(id: String, title: String, courseCode: String?, dueAt: Date?) {
            self.id = id; self.title = title; self.courseCode = courseCode; self.dueAt = dueAt
        }
    }

    /// insights-at-a-glance.md §1.2 rank 5 ("Week ahead strip").
    public nonisolated struct WeekDay: Identifiable, Equatable, Sendable {
        public let id: Date
        public let date: Date
        public let dueCount: Int
        /// `true` when the day clears `InsightsConfig.overloadMinItems` open items — the same
        /// named threshold `AlertEngine.overloadClusters` uses (§2.4 A7), reused here for a
        /// simpler per-calendar-day view rather than A7's own rolling-window scan.
        public let isBusy: Bool

        public init(id: Date, date: Date, dueCount: Int, isBusy: Bool) {
            self.id = id; self.date = date; self.dueCount = dueCount; self.isBusy = isBusy
        }
    }

    public let hero: Hero
    public let nextUp: [NextUpItem]
    public let needsAttention: [AttentionItem]
    public let dueSoon: [DueItem]
    public let weekAhead: [WeekDay]
    /// "N changes since <asOf>" — `nil` when there is nothing to show (first snapshot, or an
    /// empty digest), per insights-at-a-glance.md §1.2 rank 6.
    public let changeDigestSummary: String?

    public init(hero: Hero, nextUp: [NextUpItem], needsAttention: [AttentionItem], dueSoon: [DueItem],
                weekAhead: [WeekDay], changeDigestSummary: String?) {
        self.hero = hero; self.nextUp = nextUp; self.needsAttention = needsAttention
        self.dueSoon = dueSoon; self.weekAhead = weekAhead; self.changeDigestSummary = changeDigestSummary
    }

    public static let empty = DashboardProjection(
        hero: Hero(courseCount: 0, overallPercent: nil, overallBand: nil),
        nextUp: [], needsAttention: [], dueSoon: [], weekAhead: [], changeDigestSummary: nil)
}

/// `nonisolated`: a pure function over `CanvasSnapshot`/`ChangeDigest` values, with no UI or
/// main-thread dependency, callable from any isolation domain (including a background actor —
/// see this file's header comment and the PMO report's integration notes).
public nonisolated enum DashboardBuilder {
    /// `digest`/`digestAsOf` come from the refresh that produced `snapshot` (`nil` on the first
    /// snapshot after sign-in/entering sample mode, per architecture.md §3.4: "no digest or
    /// grade alerts on the first snapshot").
    public static func build(from snapshot: CanvasSnapshot, digest: ChangeDigest?, digestAsOf: Date?, now: Date) -> DashboardProjection {
        let coursesByID = Dictionary(uniqueKeysWithValues: snapshot.courses.map { ($0.id, $0) })

        return DashboardProjection(
            hero: hero(courses: snapshot.courses),
            nextUp: nextUp(snapshot: snapshot, coursesByID: coursesByID, now: now),
            needsAttention: needsAttention(snapshot: snapshot, coursesByID: coursesByID, now: now),
            dueSoon: dueSoon(planner: snapshot.planner, coursesByID: coursesByID, now: now),
            weekAhead: weekAhead(planner: snapshot.planner, now: now),
            changeDigestSummary: changeDigestSummary(digest: digest, asOf: digestAsOf))
    }

    // MARK: - Hero

    private static func hero(courses: [Course]) -> DashboardProjection.Hero {
        let visiblePercents = courses.compactMap { course -> Double? in
            guard course.gradeVisibility == .visible else { return nil }
            return course.scores?.currentScore
        }
        let overall = visiblePercents.isEmpty ? nil : visiblePercents.reduce(0, +) / Double(visiblePercents.count)
        return DashboardProjection.Hero(courseCount: courses.count, overallPercent: overall,
                                        overallBand: overall.map(GradeBand.fromPercent))
    }

    // MARK: - Next up (§5.1)

    /// Every assignment across every course's groups, keyed by id, with the course and its
    /// groups alongside (both needed for `PriorityScore.weight`).
    private static func openAssignments(
        in snapshot: CanvasSnapshot, coursesByID: [CanvasID<Course>: Course]
    ) -> [(course: Course, groups: [AssignmentGroup], assignment: Assignment)] {
        snapshot.groups.flatMap { courseID, groups -> [(Course, [AssignmentGroup], Assignment)] in
            guard let course = coursesByID[courseID] else { return [] }
            return groups.flatMap(\.assignments).map { (course, groups, $0) }
        }
    }

    private static func nextUp(
        snapshot: CanvasSnapshot, coursesByID: [CanvasID<Course>: Course], now: Date
    ) -> [DashboardProjection.NextUpItem] {
        var ranked: [(item: PriorityScore.RankedItem, title: String, courseCode: String)] = []
        var reasons: [CanvasID<Assignment>: String] = [:]
        let courseOrder = Dictionary(uniqueKeysWithValues: snapshot.courses.enumerated().map { ($1.id, $0) })

        for (course, groups, assignment) in openAssignments(in: snapshot, coursesByID: coursesByID) {
            guard !PriorityScore.isExcluded(assignment: assignment, markedDone: false, now: now) else { continue }
            let hours = assignment.dueAt.map { $0.timeIntervalSince(now) / 3600 }
            let weight = PriorityScore.weight(assignment: assignment, course: course, groups: groups,
                                              gradingPeriods: snapshot.gradingPeriods[course.id] ?? [])
            let modifiers = priorityModifiers(assignment: assignment, course: course, now: now)
            let score = PriorityScore.score(hoursUntilDue: hours, courseWeight: weight, modifiers: modifiers)
            ranked.append((
                PriorityScore.RankedItem(assignmentID: assignment.id, score: score, dueAt: assignment.dueAt,
                                         weight: weight, courseOrder: courseOrder[course.id] ?? .max),
                assignment.name, course.courseCode))
            reasons[assignment.id] = PriorityScore.reasonText(hoursUntilDue: hours, weight: weight,
                                                              modifiers: modifiers, courseCode: course.courseCode)
        }

        let byID = Dictionary(uniqueKeysWithValues: ranked.map { ($0.item.assignmentID, $0) })
        return PriorityScore.sorted(ranked.map(\.item)).prefix(3).map { rankedItem in
            let entry = byID[rankedItem.assignmentID]
            return DashboardProjection.NextUpItem(
                id: rankedItem.assignmentID, title: entry?.title ?? "", courseCode: entry?.courseCode ?? "",
                dueAt: rankedItem.dueAt, band: PriorityScore.band(rankedItem.score),
                reason: reasons[rankedItem.assignmentID] ?? "")
        }
    }

    private static func priorityModifiers(assignment: Assignment, course: Course, now: Date) -> PriorityScore.Modifiers {
        let overdueStillOpen: Bool = {
            guard let due = assignment.dueAt, due < now else { return false }
            return assignment.lockAt == nil || assignment.lockAt! > now
        }()
        let (belowGoal, nearBoundary) = PriorityScore.courseModifiers(currentScore: course.scores?.currentScore, goal: nil)
        return PriorityScore.Modifiers(overdueStillOpen: overdueStillOpen, courseBelowGoal: belowGoal, nearBoundary: nearBoundary)
    }

    // MARK: - Needs attention (§2)

    private static func needsAttention(
        snapshot: CanvasSnapshot, coursesByID: [CanvasID<Course>: Course], now: Date
    ) -> [DashboardProjection.AttentionItem] {
        var alerts: [(Alert, String, String?)] = []
        var loadItems: [AlertEngine.LoadItem] = []

        for (course, groups, assignment) in openAssignments(in: snapshot, coursesByID: coursesByID) {
            if let missing = AlertEngine.missingAlert(assignment: assignment, now: now) {
                alerts.append(rendered(missing, assignment: assignment, course: course))
            } else if let submission = assignment.submission, !submission.isSubmitted, !submission.excused,
                      let due = assignment.dueAt, due >= now {
                let weight = PriorityScore.weight(assignment: assignment, course: course, groups: groups,
                                                  gradingPeriods: snapshot.gradingPeriods[course.id] ?? [])
                let hours = due.timeIntervalSince(now) / 3600
                let modifiers = priorityModifiers(assignment: assignment, course: course, now: now)
                let score = PriorityScore.score(hoursUntilDue: hours, courseWeight: weight, modifiers: modifiers)
                if let dueSoon = AlertEngine.dueSoonAlert(assignment: assignment, priorityScore: score, weight: weight, now: now) {
                    alerts.append(rendered(dueSoon, assignment: assignment, course: course))
                }
            }
            if let due = assignment.dueAt, due >= now, let submission = assignment.submission,
               !submission.isSubmitted, !submission.excused {
                let weight = PriorityScore.weight(assignment: assignment, course: course, groups: groups,
                                                  gradingPeriods: snapshot.gradingPeriods[course.id] ?? [])
                loadItems.append(AlertEngine.LoadItem(dueAt: due, weight: weight, courseID: course.id))
            }
        }

        for cluster in AlertEngine.overloadClusters(loadItems, now: now) {
            guard case .overloadCluster(let start) = cluster.kind else { continue }
            alerts.append((cluster,
                          "Busy stretch starting \(Self.shortDate(start))",
                          "Several items are due close together"))
        }

        return alerts.sorted { $0.0.rank > $1.0.rank }.prefix(3)
            .map { alert, title, subtitle in
                DashboardProjection.AttentionItem(id: alert.dedupeKey, severity: alert.severity, title: title, subtitle: subtitle)
            }
    }

    private static func rendered(_ alert: Alert, assignment: Assignment, course: Course) -> (Alert, String, String?) {
        switch alert.kind {
        case .missingOpen:
            return (alert, "\(assignment.name) is missing", "\(course.courseCode) · still accepted")
        case .missingClosed:
            return (alert, "\(course.courseCode): missing work is closed", "Talk to your instructor")
        case .dueSoon:
            let due = assignment.dueAt.map(Self.shortTime) ?? ""
            return (alert, "\(assignment.name) due \(due)", course.courseCode)
        default:
            return (alert, assignment.name, course.courseCode)
        }
    }

    // MARK: - Due soon (UX review §3.7.1 item 7)

    private static func dueSoon(
        planner: [PlannerItem], coursesByID: [CanvasID<Course>: Course], now: Date
    ) -> [DashboardProjection.DueItem] {
        let horizon = now.addingTimeInterval(7 * 24 * 3600)
        return planner
            .filter { item in
                guard let due = item.dueAt, due >= now, due <= horizon else { return false }
                return !(item.markedComplete && item.submitted)
            }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            .prefix(5)
            .map { DashboardProjection.DueItem(id: $0.id, title: $0.title,
                                               courseCode: $0.courseID.flatMap { coursesByID[$0]?.courseCode }, dueAt: $0.dueAt) }
    }

    // MARK: - Week ahead (§1.2 rank 5, §1.3 "Week ahead" variant)

    private static func weekAhead(planner: [PlannerItem], now: Date) -> [DashboardProjection.WeekDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: now)
        return (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let count = planner.filter { item in
                guard let due = item.dueAt else { return false }
                return due >= day && due < nextDay
            }.count
            return DashboardProjection.WeekDay(id: day, date: day, dueCount: count,
                                               isBusy: count >= InsightsConfig.overloadMinItems)
        }
    }

    // MARK: - Change digest chip (§2.5)

    private static func changeDigestSummary(digest: ChangeDigest?, asOf: Date?) -> String? {
        guard let digest, !digest.isEmpty, let asOf else { return nil }
        let time = Self.shortTime(asOf)
        return "\(digest.count) change\(digest.count == 1 ? "" : "s") since \(time)"
    }

    // MARK: - Formatting (Foundation.Date.FormatStyle is Apple-only; TallyDomain builds on Linux)

    /// `Date.formatted(date: .omitted, time: .shortened)`'s Linux/Foundation-portable
    /// equivalent: a fixed-width 24-hour `HH:mm` in the current calendar's time zone. The
    /// source's locale-shortened time (e.g. "2:30 PM") is a presentation choice the UI layer is
    /// free to reapply from `NextUpItem.dueAt`/`AttentionItem`'s subtitle inputs; what a pure,
    /// Linux-testable domain function can portably format itself, it does.
    private static func shortTime(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// `Date.formatted(date: .abbreviated, time: .omitted)`'s portable equivalent: `yyyy-MM-dd`.
    private static func shortDate(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

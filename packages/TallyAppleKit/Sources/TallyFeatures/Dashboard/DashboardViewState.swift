import Foundation
import TallyDomain

/// UX-WP-13: a pure projection of a `CanvasSnapshot` (plus the optional glance/digest a
/// refresh just produced) into exactly what `DashboardView` renders. Building this is a plain
/// function of its inputs — no I/O, no `@Observable` ceremony — so every rule here (what makes
/// "Next up", what counts as "Needs attention", which day is "Busy") is unit-testable on its own,
/// matching the rest of this codebase's "pure function, testable on Linux" style even though this
/// particular type only ever runs on Apple platforms (it is `TallyFeatures`, not `TallyCore`).
public nonisolated struct DashboardViewState: Equatable, Sendable {
    /// insights-at-a-glance.md §1.2 rank 3 ("Compact hero"). No sparkline/delta: both need a
    /// score *history*, which this snapshot generation does not carry (R9, out of this work
    /// package's scope) — showing either would mean fabricating a trend, which the
    /// implementation brief forbids.
    public nonisolated struct Hero: Equatable, Sendable {
        public let courseCount: Int
        /// Mean of every *visible* course's current score, `nil` when no course has one to show
        /// (matches `GlanceProjectionBuilder.overallBand`'s "never shows a band it wasn't given").
        public let overallPercent: Double?
        public let overallBand: GradeBand?
    }

    /// insights-at-a-glance.md §0/§1.2 rank 1 ("Next up").
    public nonisolated struct NextUpItem: Identifiable, Equatable, Sendable {
        public let id: CanvasID<Assignment>
        public let title: String
        public let courseCode: String
        public let dueAt: Date?
        public let band: PriorityScore.Band
        public let reason: String
    }

    /// insights-at-a-glance.md §1.2 rank 2 ("Needs attention"). `subtitle` is `nil` for a bare
    /// grouped count row (e.g. "All clear" has none).
    public nonisolated struct AttentionItem: Identifiable, Equatable, Sendable {
        public let id: String
        public let severity: AlertSeverity
        public let title: String
        public let subtitle: String?
    }

    /// insights-at-a-glance.md §1.2 rank... "Due soon" (UX review §3.7.1 item 7).
    public nonisolated struct DueItem: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let courseCode: String?
        public let dueAt: Date?
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
    }

    public let hero: Hero
    public let nextUp: [NextUpItem]
    public let needsAttention: [AttentionItem]
    public let dueSoon: [DueItem]
    public let weekAhead: [WeekDay]
    /// "N changes since <asOf>" — `nil` when there is nothing to show (first snapshot, or an
    /// empty digest), per insights-at-a-glance.md §1.2 rank 6 ("Contextual: auto-shows when
    /// unseen changes exist").
    public let changeDigestSummary: String?

    public static let empty = DashboardViewState(
        hero: Hero(courseCount: 0, overallPercent: nil, overallBand: nil),
        nextUp: [], needsAttention: [], dueSoon: [], weekAhead: [], changeDigestSummary: nil)
}

/// `nonisolated`: a pure function over `CanvasSnapshot`/`ChangeDigest` values, with no UI or
/// main-thread dependency (see `DashboardViewState`'s doc comment on why this whole file opts out
/// of `TallyFeatures`'s target-wide `MainActor` default).
public nonisolated enum DashboardBuilder {
    /// `digest`/`digestAsOf` come from the refresh that produced `snapshot` (`nil` on the first
    /// snapshot after sign-in/entering sample mode, per architecture.md §3.4: "no digest or
    /// grade alerts on the first snapshot").
    public static func build(from snapshot: CanvasSnapshot, digest: ChangeDigest?, digestAsOf: Date?, now: Date) -> DashboardViewState {
        // CS-07 A8 (crash-safety-2.md §8 A1): a repeated course ID trapped here. The first
        // occurrence wins, as in TallyDomain's DashboardBuilder. This copy is deleted in step 6b.
        let coursesByID = Dictionary(snapshot.courses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        return DashboardViewState(
            hero: hero(courses: snapshot.courses),
            nextUp: nextUp(snapshot: snapshot, coursesByID: coursesByID, now: now),
            needsAttention: needsAttention(snapshot: snapshot, coursesByID: coursesByID, now: now),
            dueSoon: dueSoon(planner: snapshot.planner, coursesByID: coursesByID, now: now),
            weekAhead: weekAhead(planner: snapshot.planner, now: now),
            changeDigestSummary: changeDigestSummary(digest: digest, asOf: digestAsOf))
    }

    // MARK: - Hero

    private static func hero(courses: [Course]) -> DashboardViewState.Hero {
        let visiblePercents = courses.compactMap { course -> Double? in
            guard course.gradeVisibility == .visible else { return nil }
            return course.scores?.currentScore
        }
        let overall = visiblePercents.isEmpty ? nil : visiblePercents.reduce(0, +) / Double(visiblePercents.count)
        return DashboardViewState.Hero(courseCount: courses.count, overallPercent: overall,
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
    ) -> [DashboardViewState.NextUpItem] {
        var ranked: [(item: PriorityScore.RankedItem, title: String, courseCode: String)] = []
        var reasons: [CanvasID<Assignment>: String] = [:]
        // CS-07 A8 (§8 A2): a repeated course ID keeps its first (lowest) position.
        let courseOrder = Dictionary(snapshot.courses.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })

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

        // CS-07 A8 (§8 A3): a repeated assignment ID; the first ranked occurrence wins.
        let byID = Dictionary(ranked.map { ($0.item.assignmentID, $0) }, uniquingKeysWith: { first, _ in first })
        return PriorityScore.sorted(ranked.map(\.item)).prefix(3).map { rankedItem in
            let entry = byID[rankedItem.assignmentID]
            return DashboardViewState.NextUpItem(
                id: rankedItem.assignmentID, title: entry?.title ?? "", courseCode: entry?.courseCode ?? "",
                dueAt: rankedItem.dueAt, band: PriorityScore.band(rankedItem.score),
                reason: reasons[rankedItem.assignmentID] ?? "")
        }
    }

    private static func priorityModifiers(assignment: Assignment, course: Course, now: Date) -> PriorityScore.Modifiers {
        let overdueStillOpen: Bool = {
            guard let due = assignment.dueAt, due < now else { return false }
            return assignment.lockAt.map { $0 > now } ?? true // no lock date: still open
        }()
        let (belowGoal, nearBoundary) = PriorityScore.courseModifiers(currentScore: course.scores?.currentScore, goal: nil)
        return PriorityScore.Modifiers(overdueStillOpen: overdueStillOpen, courseBelowGoal: belowGoal, nearBoundary: nearBoundary)
    }

    // MARK: - Needs attention (§2)

    private static func needsAttention(
        snapshot: CanvasSnapshot, coursesByID: [CanvasID<Course>: Course], now: Date
    ) -> [DashboardViewState.AttentionItem] {
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
                          "Busy stretch starting \(start.formatted(date: .abbreviated, time: .omitted))",
                          "Several items are due close together"))
        }

        return alerts.sorted { $0.0.rank > $1.0.rank }.prefix(3)
            .map { alert, title, subtitle in
                DashboardViewState.AttentionItem(id: alert.dedupeKey, severity: alert.severity, title: title, subtitle: subtitle)
            }
    }

    private static func rendered(_ alert: Alert, assignment: Assignment, course: Course) -> (Alert, String, String?) {
        switch alert.kind {
        case .missingOpen:
            return (alert, "\(assignment.name) is missing", "\(course.courseCode) · still accepted")
        case .missingClosed:
            return (alert, "\(course.courseCode): missing work is closed", "Talk to your instructor")
        case .dueSoon:
            let due = assignment.dueAt.map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
            return (alert, "\(assignment.name) due \(due)", course.courseCode)
        default:
            return (alert, assignment.name, course.courseCode)
        }
    }

    // MARK: - Due soon (UX review §3.7.1 item 7)

    private static func dueSoon(
        planner: [PlannerItem], coursesByID: [CanvasID<Course>: Course], now: Date
    ) -> [DashboardViewState.DueItem] {
        let horizon = now.addingTimeInterval(7 * 24 * 3600)
        return planner
            .filter { item in
                guard let due = item.dueAt, due >= now, due <= horizon else { return false }
                return !(item.markedComplete && item.submitted)
            }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            .prefix(5)
            .map { DashboardViewState.DueItem(id: $0.id, title: $0.title,
                                              courseCode: $0.courseID.flatMap { coursesByID[$0]?.courseCode }, dueAt: $0.dueAt) }
    }

    // MARK: - Week ahead (§1.2 rank 5, §1.3 "Week ahead" variant)

    private static func weekAhead(planner: [PlannerItem], now: Date) -> [DashboardViewState.WeekDay] {
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
            return DashboardViewState.WeekDay(id: day, date: day, dueCount: count,
                                              isBusy: count >= InsightsConfig.overloadMinItems)
        }
    }

    // MARK: - Change digest chip (§2.5)

    private static func changeDigestSummary(digest: ChangeDigest?, asOf: Date?) -> String? {
        guard let digest, !digest.isEmpty, let asOf else { return nil }
        let time = asOf.formatted(date: .omitted, time: .shortened)
        return "\(digest.count) change\(digest.count == 1 ? "" : "s") since \(time)"
    }
}

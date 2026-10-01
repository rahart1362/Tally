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
///
/// Plan 08 §3.2 (L10N-02): the three fields that held English (`NextUpItem.reason`,
/// `AttentionItem.title`/`subtitle`, the digest summary) now hold values (`reasonFactors`,
/// `AttentionItem.Content`, `ChangeSummary`), which `TallyStrings.DashboardText` phrases in the
/// student's language and locale. Every rule that picks, ranks and caps the rows is unchanged.
public nonisolated struct DashboardProjection: Equatable, Sendable {
    /// insights-at-a-glance.md §1.2 rank 3 ("Compact hero"). No sparkline/delta: both need a
    /// score *history*, which this snapshot generation does not carry (R9) — showing either
    /// would mean fabricating a trend.
    ///
    /// Plan 08 §4.4 row 1 and G-5 (XG-02): the average runs over the courses whose grades are in
    /// Canvas with a current percentage (`CourseGradeStatus.averaged`), and says how many those
    /// are; every other course is counted under the reason it is left out.
    public nonisolated struct Hero: Equatable, Sendable {
        /// Every distinct course in the snapshot.
        public let courseCount: Int
        /// G-5's N in "Average of N courses": the courses `overallPercent` is the mean of.
        public let averagedCount: Int
        /// Mean of every averaged course's current score, `nil` when no course is averaged.
        public let overallPercent: Double?
        public let overallBand: GradeBand?
        /// The courses left out of the average, by reason (never `.averaged`); with
        /// `averagedCount` they add up to `courseCount`.
        public let exclusions: [CourseGradeStatus: Int]
        /// Plan 08 §4.2's school-level summary. With nothing averaged, `.noneInCanvas` is the
        /// "Grades aren't in Canvas" state (G-5).
        public let school: SchoolGradeSummary

        public init(courseCount: Int, averagedCount: Int, overallPercent: Double?, overallBand: GradeBand?,
                    exclusions: [CourseGradeStatus: Int], school: SchoolGradeSummary) {
            self.courseCount = courseCount
            self.averagedCount = averagedCount
            self.overallPercent = overallPercent
            self.overallBand = overallBand
            self.exclusions = exclusions
            self.school = school
        }
    }

    /// insights-at-a-glance.md §0/§1.2 rank 1 ("Next up").
    public nonisolated struct NextUpItem: Identifiable, Equatable, Sendable {
        public let id: CanvasID<Assignment>
        public let title: String
        public let courseCode: String
        public let dueAt: Date?
        public let band: PriorityScore.Band
        /// Why it ranks here: the due-date clause, then up to two modifiers
        /// (`PriorityScore.reasonFactors`). Plan 08 §3.2 (L10N-02): TallyCore emits no text; the
        /// app phrases these (`TallyStrings.DashboardText.reason`).
        public let reasonFactors: [PriorityScore.Factor]

        public init(id: CanvasID<Assignment>, title: String, courseCode: String, dueAt: Date?,
                    band: PriorityScore.Band, reasonFactors: [PriorityScore.Factor]) {
            self.id = id; self.title = title; self.courseCode = courseCode; self.dueAt = dueAt
            self.band = band; self.reasonFactors = reasonFactors
        }
    }

    /// insights-at-a-glance.md §1.2 rank 2 ("Needs attention"). Plan 08 §3.2 (L10N-02): the row
    /// says what `content` holds, phrased by the app (`TallyStrings.DashboardText`).
    public nonisolated struct AttentionItem: Identifiable, Equatable, Sendable {
        /// What one "Needs attention" row is about. Titles and course codes are Canvas's, passed
        /// through untouched; dates are formatted by the app in the student's locale.
        public nonisolated enum Content: Equatable, Sendable {
            /// A1: missing and still accepted.
            case missingOpen(title: String, courseCode: String)
            /// A2: missing work in this course is closed.
            case missingClosed(courseCode: String)
            /// A3: due soon, at `dueAt`.
            case dueSoon(title: String, dueAt: Date, courseCode: String)
            /// A7: several items due close together, from `start`.
            case overload(start: Date)
            /// Any other alert about an assignment: its title and course code.
            case other(title: String, courseCode: String)
        }

        public let id: String
        public let severity: AlertSeverity
        public let content: Content

        public init(id: String, severity: AlertSeverity, content: Content) {
            self.id = id; self.severity = severity; self.content = content
        }
    }

    /// insights-at-a-glance.md §1.2 rank 6: "N changes since <asOf>". Plan 08 §3.2 (L10N-02): a
    /// count and a time, phrased and formatted by the app (`TallyStrings.DashboardText`).
    public nonisolated struct ChangeSummary: Equatable, Sendable {
        public let count: Int
        public let asOf: Date

        public init(count: Int, asOf: Date) {
            self.count = count; self.asOf = asOf
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
    public let changeDigestSummary: ChangeSummary?

    public init(hero: Hero, nextUp: [NextUpItem], needsAttention: [AttentionItem], dueSoon: [DueItem],
                weekAhead: [WeekDay], changeDigestSummary: ChangeSummary?) {
        self.hero = hero; self.nextUp = nextUp; self.needsAttention = needsAttention
        self.dueSoon = dueSoon; self.weekAhead = weekAhead; self.changeDigestSummary = changeDigestSummary
    }

    public static let empty = DashboardProjection(
        hero: Hero(courseCount: 0, averagedCount: 0, overallPercent: nil, overallBand: nil, exclusions: [:],
                   school: .undetermined),
        nextUp: [], needsAttention: [], dueSoon: [], weekAhead: [], changeDigestSummary: nil)
}

/// Plan 08 §4.4 (XG-02): what Tally can do with one course's grade, from its `GradeAvailability`.
/// One rule for every grade-derived number: the dashboard hero's average, the glance's band and
/// its averaged count, and the widget all read this. Only `.averaged` courses feed an average.
///
/// The raw values are a persisted contract: the glance (schema 2) stores one per course.
/// `GradeAvailability` itself is not `Codable` (XG-01); this is its glance encoding, minus the
/// evidence counts, plus the split of in-Canvas courses into averaged or not.
public nonisolated enum CourseGradeStatus: String, Codable, Hashable, Sendable, CaseIterable {
    /// In Canvas with a current percentage: counted in the average.
    case averaged
    /// In Canvas and shown as percentages, but Canvas sent no current course percentage to
    /// average (a current letter grade only, or a grading-period score only).
    case noPercentage
    /// In Canvas, letters only (`restrict_quantitative_data`).
    case lettersOnly
    /// In Canvas, but the instructor hides the course total.
    case hiddenByInstructor
    /// No grade yet (today's "No grade yet").
    case notYetPosted
    /// The course has no graded work in Canvas (advisory, homeroom).
    case notGradedInCanvas
    /// The course's grades do not appear to be kept in Canvas.
    case keptOutsideCanvas

    /// `availability` is the course's state in the index; `nil` (a course the index was not
    /// built from) counts as not yet posted, so nothing grade-derived is shown for it.
    public init(course: Course, availability: GradeAvailability?) {
        switch availability {
        case .available?: self = course.scores?.currentScore != nil ? .averaged : .noPercentage
        case .lettersOnly?: self = .lettersOnly
        case .hiddenByInstructor?: self = .hiddenByInstructor
        case .notYetPosted?, nil: self = .notYetPosted
        case .notGradedInCanvas?: self = .notGradedInCanvas
        case .keptOutsideCanvas?: self = .keptOutsideCanvas
        }
    }

    /// The state `SchoolGradeSummary` counts for this status. A glance stores no evidence counts,
    /// and the summary reads none, so `.keptOutsideCanvas` maps to empty evidence.
    var summaryState: GradeAvailability {
        switch self {
        case .averaged, .noPercentage: .available
        case .lettersOnly: .lettersOnly
        case .hiddenByInstructor: .hiddenByInstructor
        case .notYetPosted: .notYetPosted
        case .notGradedInCanvas: .notGradedInCanvas
        case .keptOutsideCanvas: .keptOutsideCanvas(.init(pastDueItems: 0, submittedOrOfflineItems: 0))
        }
    }
}

extension SchoolGradeSummary {
    /// The summary over per-course statuses: the same as over the `GradeAvailability` states they
    /// came from (the launch paint reads the statuses from the glance).
    public init(statuses: some Sequence<CourseGradeStatus>) {
        self.init(states: statuses.lazy.map(\.summaryState))
    }
}

/// `nonisolated`: a pure function over `CanvasSnapshot`/`ChangeDigest` values, with no UI or
/// main-thread dependency, callable from any isolation domain (including a background actor —
/// see this file's header comment and the PMO report's integration notes).
public nonisolated enum DashboardBuilder {
    /// `digest`/`digestAsOf` come from the refresh that produced `snapshot` (`nil` on the first
    /// snapshot after sign-in/entering sample mode, per architecture.md §3.4: "no digest or
    /// grade alerts on the first snapshot").
    ///
    /// This form classifies the courses itself, with no per-course override (plan 08 G-3): for
    /// tests and tools. The app passes the index it built once for this snapshot, its overrides
    /// and `now` (`build(from:digest:digestAsOf:now:gradeAvailability:)`).
    public static func build(from snapshot: CanvasSnapshot, digest: ChangeDigest?, digestAsOf: Date?, now: Date) -> DashboardProjection {
        build(from: snapshot, digest: digest, digestAsOf: digestAsOf, now: now,
              gradeAvailability: GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: now))
    }

    /// Plan 08 §4.3 (XG-02): `gradeAvailability` is built once per (snapshot, overrides, now) by
    /// the caller (`HomeProjector`, off the main actor) and drives every grade-derived value here:
    /// the hero's average (§4.4 row 1), the near-boundary and below-goal modifiers (row 11), and
    /// the course-weight reason (row 12). A course the index does not know shows nothing
    /// grade-derived.
    public static func build(from snapshot: CanvasSnapshot, digest: ChangeDigest?, digestAsOf: Date?, now: Date,
                             gradeAvailability: GradeAvailabilityIndex) -> DashboardProjection {
        // CS-07: `courses` can repeat an ID (a course listed once per enrollment, or pages that
        // overlap). `Dictionary(uniqueKeysWithValues:)` trapped on that. The first occurrence
        // wins, as in `PriorityScore.WeightContext`.
        let coursesByID = Dictionary(snapshot.courses.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // PERF-03: computed once and shared by `nextUp`/`needsAttention` below, which used to
        // each rebuild this (a `flatMap` over every course's every assignment group) from
        // scratch, AND each independently recompute `PriorityScore.weight` per item --
        // `needsAttention` alone could call it up to twice for the same item (its dueSoonAlert
        // branch and its loadItems branch), on top of `nextUp`'s own call. `weight` is the
        // expensive part of that trio (it walks the item's assignment group and, for a
        // grading-period course, searches the course's periods -- `priorityModifiers`/`score`
        // are cheap arithmetic by comparison), so it is the one computed once here and threaded
        // through both, rather than three names for the same lookup. Same set, same order, same
        // weight values (still `PriorityScore.weight`'s, computed exactly once per item now
        // instead of up to three times, and since PERF-05 from one precomputed
        // `PriorityScore.WeightContext` per course) -- a pure hoist, not a rule change.
        let items = scoredAssignments(in: snapshot, coursesByID: coursesByID)

        return DashboardProjection(
            hero: hero(courses: snapshot.courses, gradeAvailability: gradeAvailability),
            nextUp: nextUp(items: items, snapshot: snapshot, gradeAvailability: gradeAvailability, now: now),
            needsAttention: needsAttention(items: items, snapshot: snapshot, gradeAvailability: gradeAvailability, now: now),
            dueSoon: dueSoon(planner: snapshot.planner, coursesByID: coursesByID, now: now),
            weekAhead: weekAhead(planner: snapshot.planner, now: now),
            changeDigestSummary: changeDigestSummary(digest: digest, asOf: digestAsOf))
    }

    // MARK: - Hero

    /// Plan 08 §4.4 row 1 (G-5): the mean of the averaged courses' current scores, how many those
    /// are, why each other course is left out, and the school summary. Public so the glance
    /// (`GlanceProjectionBuilder`, §4.4 row 15) applies the same rule. A repeated course ID
    /// counts once, at its first occurrence (CS-07, as in the index).
    public static func hero(courses: [Course], gradeAvailability: GradeAvailabilityIndex) -> DashboardProjection.Hero {
        var seen = Set<CanvasID<Course>>()
        var statuses: [CourseGradeStatus] = []
        var percents: [Double] = []
        var exclusions: [CourseGradeStatus: Int] = [:]
        for course in courses where seen.insert(course.id).inserted {
            let status = CourseGradeStatus(course: course, availability: gradeAvailability[course.id])
            statuses.append(status)
            if status == .averaged, let percent = course.scores?.currentScore {
                percents.append(percent)
            } else {
                exclusions[status, default: 0] += 1
            }
        }
        let overall = percents.isEmpty ? nil : percents.reduce(0, +) / Double(percents.count)
        return DashboardProjection.Hero(courseCount: statuses.count, averagedCount: percents.count, overallPercent: overall,
                                        overallBand: overall.map(GradeBand.fromPercent), exclusions: exclusions,
                                        school: SchoolGradeSummary(statuses: statuses))
    }

    /// Plan 08 §4.4 rows 11 and 18: the current score a priority modifier (near a grade boundary,
    /// below goal) may use. Only a course whose grades are in Canvas and shown as percentages
    /// (`.available`) has one; for every other state it is nil, so neither modifier fires.
    public static func modifierScore(of course: Course, availability: GradeAvailability?) -> Double? {
        availability == .available ? course.scores?.currentScore : nil
    }

    // MARK: - Next up (§5.1)

    /// Every assignment across every course's groups, each with its `PriorityScore.weight`
    /// computed exactly once (see `build(from:...)`'s comment on why weight specifically).
    ///
    /// PERF-05 PA-2: from one `PriorityScore.WeightContext` per course. Calling
    /// `PriorityScore.weight` per item re-summed the item's whole group or course each time,
    /// O(n²·p) per course; the context sums each course once. Same values, bit for bit
    /// (`PriorityWeightDifferentialTests`).
    private static func scoredAssignments(
        in snapshot: CanvasSnapshot, coursesByID: [CanvasID<Course>: Course]
    ) -> [(course: Course, groups: [AssignmentGroup], assignment: Assignment, weight: Double)] {
        snapshot.groups.flatMap { courseID, groups -> [(Course, [AssignmentGroup], Assignment, Double)] in
            guard let course = coursesByID[courseID] else { return [] }
            let weights = PriorityScore.WeightContext(course: course, groups: groups,
                                                      gradingPeriods: snapshot.gradingPeriods[course.id] ?? [])
            return groups.flatMap(\.assignments).map { assignment in
                (course, groups, assignment, weights.weight(of: assignment))
            }
        }
    }

    /// Plan 08 §4.4 row 12: for a course whose grades are not in Canvas, the course-weight factor
    /// ("~12% of BIO 101") is dropped from the reason, since its share of an external grade is
    /// unknown. Its ranking weight is unchanged: points still signal effort.
    private static func nextUp(
        items: [(course: Course, groups: [AssignmentGroup], assignment: Assignment, weight: Double)],
        snapshot: CanvasSnapshot, gradeAvailability: GradeAvailabilityIndex, now: Date
    ) -> [DashboardProjection.NextUpItem] {
        var ranked: [(item: PriorityScore.RankedItem, title: String, courseCode: String)] = []
        var reasons: [CanvasID<Assignment>: [PriorityScore.Factor]] = [:]
        // CS-07: a repeated course ID keeps its first (lowest) position instead of trapping.
        let courseOrder = Dictionary(snapshot.courses.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })

        for (course, _, assignment, weight) in items {
            guard !PriorityScore.isExcluded(assignment: assignment, markedDone: false, now: now) else { continue }
            let hours = assignment.dueAt.map { $0.timeIntervalSince(now) / 3600 }
            let availability = gradeAvailability[course.id]
            let modifiers = priorityModifiers(assignment: assignment, course: course, availability: availability, now: now)
            let score = PriorityScore.score(hoursUntilDue: hours, courseWeight: weight, modifiers: modifiers)
            ranked.append((
                PriorityScore.RankedItem(assignmentID: assignment.id, score: score, dueAt: assignment.dueAt,
                                         weight: weight, courseOrder: courseOrder[course.id] ?? .max),
                assignment.name, course.courseCode))
            let factors = PriorityScore.reasonFactors(hoursUntilDue: hours, weight: weight, modifiers: modifiers)
            reasons[assignment.id] = availability?.isInCanvas == true ? factors : factors.filter { !$0.isCourseWeight }
        }

        // CS-07: an assignment ID can repeat (within a group, across groups or across courses);
        // `Dictionary(uniqueKeysWithValues:)` trapped on that. The first ranked occurrence wins.
        let byID = Dictionary(ranked.map { ($0.item.assignmentID, $0) }, uniquingKeysWith: { first, _ in first })
        return PriorityScore.sorted(ranked.map(\.item)).prefix(3).map { rankedItem in
            let entry = byID[rankedItem.assignmentID]
            return DashboardProjection.NextUpItem(
                id: rankedItem.assignmentID, title: entry?.title ?? "", courseCode: entry?.courseCode ?? "",
                dueAt: rankedItem.dueAt, band: PriorityScore.band(rankedItem.score),
                reasonFactors: reasons[rankedItem.assignmentID] ?? [])
        }
    }

    /// Plan 08 §4.4 row 11: the course modifiers see a score only when the course is `.available`
    /// (`modifierScore`). Under the strict rule (G-2) an excluded course has no score anyway; this
    /// is the guard for an override (G-3) or a looser rule.
    private static func priorityModifiers(assignment: Assignment, course: Course, availability: GradeAvailability?,
                                          now: Date) -> PriorityScore.Modifiers {
        let overdueStillOpen: Bool = {
            guard let due = assignment.dueAt, due < now else { return false }
            return assignment.lockAt.map { $0 > now } ?? true // no lock date: still open
        }()
        let (belowGoal, nearBoundary) = PriorityScore.courseModifiers(
            currentScore: modifierScore(of: course, availability: availability), goal: nil)
        return PriorityScore.Modifiers(overdueStillOpen: overdueStillOpen, courseBelowGoal: belowGoal, nearBoundary: nearBoundary)
    }

    // MARK: - Needs attention (§2)

    private static func needsAttention(
        items: [(course: Course, groups: [AssignmentGroup], assignment: Assignment, weight: Double)],
        snapshot: CanvasSnapshot, gradeAvailability: GradeAvailabilityIndex, now: Date
    ) -> [DashboardProjection.AttentionItem] {
        var alerts: [(Alert, DashboardProjection.AttentionItem.Content)] = []
        var loadItems: [AlertEngine.LoadItem] = []

        for (course, _, assignment, weight) in items {
            if let missing = AlertEngine.missingAlert(assignment: assignment, now: now) {
                alerts.append((missing, content(of: missing, assignment: assignment, course: course)))
            } else if let submission = assignment.submission, !submission.isSubmitted, !submission.excused,
                      let due = assignment.dueAt, due >= now {
                let hours = due.timeIntervalSince(now) / 3600
                let modifiers = priorityModifiers(assignment: assignment, course: course,
                                                  availability: gradeAvailability[course.id], now: now)
                let score = PriorityScore.score(hoursUntilDue: hours, courseWeight: weight, modifiers: modifiers)
                if let dueSoon = AlertEngine.dueSoonAlert(assignment: assignment, priorityScore: score, weight: weight, now: now) {
                    alerts.append((dueSoon, content(of: dueSoon, assignment: assignment, course: course)))
                }
            }
            if let due = assignment.dueAt, due >= now, let submission = assignment.submission,
               !submission.isSubmitted, !submission.excused {
                loadItems.append(AlertEngine.LoadItem(dueAt: due, weight: weight, courseID: course.id))
            }
        }

        for cluster in AlertEngine.overloadClusters(loadItems, now: now) {
            guard case .overloadCluster(let start) = cluster.kind else { continue }
            alerts.append((cluster, .overload(start: start)))
        }

        return uniqueByDedupeKey(alerts).sorted { $0.0.rank > $1.0.rank }.prefix(3)
            .map { alert, content in
                DashboardProjection.AttentionItem(id: alert.dedupeKey, severity: alert.severity, content: content)
            }
    }

    /// R-3 (resilience.md): one row per `dedupeKey`, which is each row's `id`, so the list never
    /// repeats an ID (SwiftUI's `ForEach` needs unique IDs). Valid data repeats a key: A2 groups
    /// closed missing work per course (`missingClosed:<course>`), so two closed missing
    /// assignments in one course raised two alerts with one key. The row kept for a key has the
    /// highest severity, then comes first; it takes the place of the key's first alert.
    private static func uniqueByDedupeKey(
        _ alerts: [(Alert, DashboardProjection.AttentionItem.Content)]
    ) -> [(Alert, DashboardProjection.AttentionItem.Content)] {
        var unique: [(Alert, DashboardProjection.AttentionItem.Content)] = []
        var position: [String: Int] = [:]
        for entry in alerts {
            let key = entry.0.dedupeKey
            guard let index = position[key] else {
                position[key] = unique.count
                unique.append(entry)
                continue
            }
            if entry.0.severity > unique[index].0.severity { unique[index] = entry }
        }
        return unique
    }

    private static func content(
        of alert: Alert, assignment: Assignment, course: Course
    ) -> DashboardProjection.AttentionItem.Content {
        switch alert.kind {
        case .missingOpen:
            return .missingOpen(title: assignment.name, courseCode: course.courseCode)
        case .missingClosed:
            return .missingClosed(courseCode: course.courseCode)
        case .dueSoon:
            // `AlertEngine.dueSoonAlert` raises A3 only for an item with a due date.
            guard let due = assignment.dueAt else { return .other(title: assignment.name, courseCode: course.courseCode) }
            return .dueSoon(title: assignment.name, dueAt: due, courseCode: course.courseCode)
        default:
            return .other(title: assignment.name, courseCode: course.courseCode)
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

    /// Plan 08 §3.2 (L10N-02): the count and the time only. The fixed-format `HH:mm` and
    /// `yyyy-MM-dd` text the port used to build here (24-hour time and an ISO date for every
    /// user) is gone; the app formats both in the student's locale.
    private static func changeDigestSummary(digest: ChangeDigest?, asOf: Date?) -> DashboardProjection.ChangeSummary? {
        guard let digest, !digest.isEmpty, let asOf else { return nil }
        return DashboardProjection.ChangeSummary(count: digest.count, asOf: asOf)
    }
}

private extension PriorityScore.Factor {
    var isCourseWeight: Bool {
        if case .courseWeight = self { return true }
        return false
    }
}

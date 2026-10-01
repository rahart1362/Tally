import Foundation
import TallyDomain

/// "92% on time this term" (ux-ui.md §3.7.6 Completion).
public nonisolated struct CompletionInsight: Equatable, Sendable {
    public let onTime: Int
    public let due: Int
    /// 0...1.
    public let share: Double
    public let headline: String
    public let detail: String
}

/// "3-day streak" (ux-ui.md §3.7.6 Momentum), with its definition stated, as the spec requires.
public nonisolated struct StreakInsight: Equatable, Sendable {
    public let days: Int
    public let headline: String
    public static let definition = "Days in a row, up to today, on which you submitted at least one assignment."
}

/// A course that needs a look, and why (ux-ui.md §3.7.6 "At risk": courses with reasons).
public nonisolated struct CourseRisk: Identifiable, Equatable, Sendable {
    public let id: CanvasID<Course>
    public let code: String
    public let name: String
    public let health: CourseHealth
    public let reasons: [String]
    public let accessibilityLabel: String
}

/// "6 items due Oct 12–13" (ux-ui.md §3.7.6 Heavy weeks; insights-at-a-glance.md §2.1 A7).
public nonisolated struct HeavyStretch: Identifiable, Equatable, Sendable {
    public let id: Date
    public let headline: String
    public let detail: String
}

/// The grade-trend chart's input: each course's `GradeInput` and when each score was posted. The
/// trend itself is grade math (`GradeTrend`, through `GradeWork`); R9: derived from graded history,
/// never a stored time series.
public nonisolated struct TrendInput: Equatable, Sendable {
    public nonisolated struct CourseHistory: Equatable, Sendable {
        public let id: CanvasID<Course>
        public let input: GradeInput
        public let postedAt: [CanvasID<Assignment>: Date]
    }

    public let courses: [CourseHistory]
    /// The earliest term start among the courses ("Term" range), if Canvas gave one.
    public let termStart: Date?
    public let now: Date

    public static let empty = TrendInput(courses: [], termStart: nil, now: .distantPast)
}

/// Insights (ux-ui.md §3.7.6, UX-WP-19; PMO R13), except the grade trend, which `InsightsModel`
/// computes through `GradeWork`. Built off the main actor.
public nonisolated struct InsightsProjection: Equatable, Sendable {
    public let completion: CompletionInsight?
    public let streak: StreakInsight
    public let risks: [CourseRisk]
    public let heavyStretches: [HeavyStretch]
    /// What grades are made of, across every course whose grades are in Canvas (`chart.weights`).
    public let categoryShares: [CategoryWeight]
    public let categorySummary: String
    public let trendInput: TrendInput
    /// Plan 08 §4.4 row 7 (XG-03): no course qualifies for the trend, and at least one is left out
    /// because its grades are kept outside Canvas. The trend card then says "Trends appear when
    /// grades are posted in Canvas." instead of drawing an empty chart.
    public var trendIsNotInCanvas = false

    public static let empty = InsightsProjection(
        completion: nil, streak: StreakInsight(days: 0, headline: "No current streak"), risks: [],
        heavyStretches: [], categoryShares: [], categorySummary: "", trendInput: .empty)
}

/// Builds Insights from one snapshot (pure; unit-tested).
public nonisolated enum InsightsBuilder {
    /// Categories shown in the breakdown before the rest are summed as "Other".
    static let categoryLimit = 5

    /// - Parameter gradeAvailability: the projection's `GradeAvailabilityIndex` (plan 08 §4.3);
    ///   `nil` classifies the snapshot at `formatter.now` with no override. Completion, momentum
    ///   and heavy stretches are submission-based and do not read it (§4.4 row 9).
    public static func projection(from snapshot: CanvasSnapshot, formatter: ScreenFormatter,
                                  gradeAvailability: GradeAvailabilityIndex? = nil) -> InsightsProjection {
        let index = gradeAvailability ?? GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: formatter.now)
        let (shares, summary) = categoryShares(snapshot, gradeAvailability: index, formatter: formatter)
        let trend = trendInput(snapshot, gradeAvailability: index, now: formatter.now)
        var projection = InsightsProjection(
            completion: completion(snapshot, now: formatter.now),
            streak: streak(snapshot, formatter: formatter),
            risks: risks(snapshot, gradeAvailability: index, formatter: formatter),
            heavyStretches: heavyStretches(snapshot, formatter: formatter),
            categoryShares: shares, categorySummary: summary,
            trendInput: trend)
        projection.trendIsNotInCanvas = trend.courses.isEmpty
            && index.byCourse.values.contains { if case .keptOutsideCanvas = $0 { true } else { false } }
        return projection
    }

    // MARK: - Completion: on time this term

    /// Of the work that was due before now and expected an online submission (excused work left
    /// out), the share submitted on time: submitted, and not late.
    static func completion(_ snapshot: CanvasSnapshot, now: Date) -> CompletionInsight? {
        var due = 0
        var onTime = 0
        for assignment in uniqueAssignments(snapshot) {
            guard let dueAt = assignment.dueAt, dueAt < now, expectsOnlineSubmission(assignment),
                  assignment.submission?.excused != true else { continue }
            due += 1
            if let submission = assignment.submission, submission.isSubmitted, !submission.late { onTime += 1 }
        }
        guard due > 0 else { return nil }
        let share = Double(onTime) / Double(due)
        let percent = Int((share * 100).rounded())
        return CompletionInsight(onTime: onTime, due: due, share: share,
                                 headline: "\(percent)% on time this term",
                                 detail: "\(onTime) of \(due) past-due assignments were submitted on time.")
    }

    // MARK: - Momentum: submission streak

    static func streak(_ snapshot: CanvasSnapshot, formatter: ScreenFormatter) -> StreakInsight {
        let calendar = formatter.calendar
        let days = Set(uniqueAssignments(snapshot).compactMap { $0.submission?.submittedAt }
            .filter { $0 <= formatter.now }
            .map { calendar.startOfDay(for: $0) })
        let today = calendar.startOfDay(for: formatter.now)
        // A streak still counts today until the day is over: it may end yesterday.
        var day = days.contains(today) ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return StreakInsight(days: count, headline: count == 0 ? "No current streak"
                                                  : count == 1 ? "1-day streak" : "\(count)-day streak")
    }

    // MARK: - At risk

    /// Plan 08 §4.4 row 10: the grade reasons (below the goal, near a cutoff) only for a course
    /// whose grades are in Canvas as percentages; the missing-work reasons for every course.
    static func risks(_ snapshot: CanvasSnapshot, gradeAvailability: GradeAvailabilityIndex,
                      formatter: ScreenFormatter) -> [CourseRisk] {
        var seen = Set<CanvasID<Course>>()
        let rows = snapshot.courses.compactMap { course -> CourseRisk? in
            guard seen.insert(course.id).inserted else { return nil }
            let evaluation = CourseHealthRules.evaluate(
                course: course, groups: snapshot.groups[course.id] ?? [],
                gradingPeriods: snapshot.gradingPeriods[course.id] ?? [],
                availability: gradeAvailability[course.id], formatter: formatter)
            guard evaluation.health == .atRisk || evaluation.health == .needsAttention else { return nil }
            let spoken = ([course.name, course.courseCode, evaluation.health.label] + evaluation.reasons)
                .joined(separator: ", ")
            return CourseRisk(id: course.id, code: course.courseCode, name: course.name, health: evaluation.health,
                              reasons: evaluation.reasons, accessibilityLabel: spoken)
        }
        // At risk first, then Canvas order (stable).
        return rows.enumerated()
            .sorted { a, b in
                let ra = a.element.health == .atRisk ? 0 : 1
                let rb = b.element.health == .atRisk ? 0 : 1
                return ra != rb ? ra < rb : a.offset < b.offset
            }
            .map(\.element)
    }

    // MARK: - Heavy stretches (A7 overload)

    static func heavyStretches(_ snapshot: CanvasSnapshot, formatter: ScreenFormatter) -> [HeavyStretch] {
        let now = formatter.now
        var items: [AlertEngine.LoadItem] = []
        var seenCourses = Set<CanvasID<Course>>()
        var seenAssignments = Set<CanvasID<Assignment>>()
        for course in snapshot.courses where seenCourses.insert(course.id).inserted {
            let groups = snapshot.groups[course.id] ?? []
            let weights = PriorityScore.WeightContext(course: course, groups: groups,
                                                      gradingPeriods: snapshot.gradingPeriods[course.id] ?? [])
            for assignment in groups.flatMap(\.assignments) where assignment.published {
                guard seenAssignments.insert(assignment.id).inserted,
                      let due = assignment.dueAt, due >= now, let submission = assignment.submission,
                      !submission.isSubmitted, !submission.excused else { continue }
                items.append(AlertEngine.LoadItem(dueAt: due, weight: weights.weight(of: assignment), courseID: course.id))
            }
        }
        let window = InsightsConfig.overloadWindow.timeInterval
        return AlertEngine.overloadClusters(items, now: now).compactMap { alert in
            guard case .overloadCluster(let start) = alert.kind else { return nil }
            let inWindow = items.filter { $0.dueAt >= start && $0.dueAt < start.addingTimeInterval(window) }
            guard let last = inWindow.map(\.dueAt).max() else { return nil }
            let first = formatter.shortDate(start)
            let end = formatter.shortDate(last)
            let range = first == end ? first : "\(first)–\(end)"
            let courses = Set(inWindow.map(\.courseID)).count
            return HeavyStretch(
                id: start, headline: "\(inWindow.count) items due \(range)",
                detail: courses == 1 ? "All in one course." : "Across \(courses) courses.")
        }
    }

    // MARK: - Category breakdown (chart.weights)

    /// Each category's average share of a course grade across every course: a course without the
    /// category counts as 0, so the shares add up to the whole. Categories are matched by name,
    /// ignoring case; beyond `categoryLimit`, the rest are summed as "Other".
    ///
    /// Plan 08 §4.4 row 8: a course whose grades are kept outside Canvas, or that has no graded
    /// work in Canvas, is left out (Canvas's group weights don't describe its grade). With nothing
    /// left, the section is hidden.
    static func categoryShares(_ snapshot: CanvasSnapshot, gradeAvailability: GradeAvailabilityIndex,
                               formatter: ScreenFormatter) -> ([CategoryWeight], String) {
        var seen = Set<CanvasID<Course>>()
        let courses = snapshot.courses.filter { course in
            guard seen.insert(course.id).inserted else { return false }
            switch gradeAvailability[course.id] {
            case .keptOutsideCanvas?, .notGradedInCanvas?: return false
            case .available?, .lettersOnly?, .hiddenByInstructor?, .notYetPosted?, nil: return true
            }
        }
        guard !courses.isEmpty else { return ([], "") }
        var totals: [String: (name: String, share: Double, order: Int)] = [:]
        var contributing = 0
        for course in courses {
            let weights = CourseDetailBuilder.categoryWeights(course: course, groups: snapshot.groups[course.id] ?? [],
                                                              formatter: formatter)
            let sum = weights.reduce(0) { $0 + $1.share }
            guard sum > 0 else { continue }
            contributing += 1
            for weight in weights {
                let key = weight.name.lowercased()
                let entry = totals[key] ?? (weight.name, 0, totals.count)
                // Normalised per course, so a course whose weights do not add to 100% still counts once.
                totals[key] = (entry.name, entry.share + weight.share / sum, entry.order)
            }
        }
        guard contributing > 0 else { return ([], "") }
        let ranked = totals.values
            .map { (name: $0.name, share: $0.share / Double(contributing), order: $0.order) }
            .sorted { $0.share != $1.share ? $0.share > $1.share : $0.order < $1.order }
        var shown = ranked.prefix(categoryLimit).map { entry in
            CategoryWeight(id: entry.name.lowercased(), name: entry.name, share: entry.share,
                           shareText: formatter.shareText(entry.share))
        }
        let rest = ranked.dropFirst(categoryLimit).reduce(0) { $0 + $1.share }
        if rest > 0 {
            shown.append(CategoryWeight(id: "other", name: "Other", share: rest, shareText: formatter.shareText(rest)))
        }
        return (shown, shown.map { "\($0.name) \($0.shareText)" }.joined(separator: ", "))
    }

    // MARK: - Trend input (R9)

    /// Plan 08 §4.4 row 7: only courses whose grades are in Canvas as percentages (`.available`).
    static func trendInput(_ snapshot: CanvasSnapshot, gradeAvailability: GradeAvailabilityIndex, now: Date) -> TrendInput {
        var seen = Set<CanvasID<Course>>()
        var courses: [TrendInput.CourseHistory] = []
        var termStart: Date?
        for course in snapshot.courses
        where seen.insert(course.id).inserted && gradeAvailability[course.id] == .available {
            let groups = snapshot.groups[course.id] ?? []
            var posted: [CanvasID<Assignment>: Date] = [:]
            for assignment in groups.flatMap(\.assignments) {
                if let date = assignment.submission?.postedAt, date <= now, posted[assignment.id] == nil {
                    posted[assignment.id] = date
                }
            }
            guard !posted.isEmpty else { continue }
            courses.append(TrendInput.CourseHistory(
                id: course.id,
                input: GradeInput(course: course, groups: groups, gradingPeriods: snapshot.gradingPeriods[course.id] ?? []),
                postedAt: posted))
            if let start = course.term?.startAt, start < (termStart ?? .distantFuture) { termStart = start }
        }
        return TrendInput(courses: courses, termStart: termStart, now: now)
    }

    // MARK: - Helpers

    static func uniqueAssignments(_ snapshot: CanvasSnapshot) -> [Assignment] {
        var seen = Set<CanvasID<Assignment>>()
        return snapshot.courses.flatMap { snapshot.groups[$0.id] ?? [] }
            .flatMap(\.assignments)
            .filter { $0.published && seen.insert($0.id).inserted }
    }

    static func expectsOnlineSubmission(_ assignment: Assignment) -> Bool {
        assignment.isGradeable && !(!assignment.submissionTypes.isEmpty
            && assignment.submissionTypes.allSatisfy { $0 == "none" || $0 == "on_paper" })
    }
}

import Foundation
import TallyDomain
import TallyStrings

/// One category's share of a course grade: the category-weights chart (`chart.weights`, ux-ui.md
/// §3.5 "horizontal BarMark with direct labels") and the Grades table.
public nonisolated struct CategoryWeight: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// 0...1.
    public let share: Double
    /// "30%".
    public let shareText: String
}

/// A graded item with its score chip (icon plus "92/100", ux-ui.md §3.7.3).
public nonisolated struct GradedItem: Identifiable, Equatable, Sendable {
    public let id: CanvasID<Assignment>
    public let title: String
    /// "92/100", a letter for a letters-only course, or "Excused".
    public let scoreText: String
    /// "Posted Mon".
    public let postedText: String?
    public let accessibilityLabel: String
}

/// A row of the Assignments segment: never a navigation row, so no chevron (ux-ui.md §3.7.7's rule
/// applies to every list).
public nonisolated struct CourseAssignmentRow: Identifiable, Equatable, Sendable {
    public let id: CanvasID<Assignment>
    public let title: String
    public let dueText: String?
    public let status: WorkStatus?
    /// "92/100" once graded; `nil` otherwise.
    public let scoreText: String?
    public let accessibilityLabel: String
}

public nonisolated struct CourseAssignmentSection: Identifiable, Equatable, Sendable {
    public nonisolated enum Kind: String, Equatable, Sendable, CaseIterable {
        case upcoming, missing, submitted, graded, past
    }

    public var id: Kind { kind }
    public let kind: Kind
    public let title: String
    public let rows: [CourseAssignmentRow]
}

/// The Grades segment's static part: category, weight, and whether a percentage may be shown. The
/// current percentage per category is grade math, computed off the main actor through `GradeWork`
/// by `CourseGradesModel`.
public nonisolated struct CategoryRow: Identifiable, Equatable, Sendable {
    public let id: CanvasID<AssignmentGroup>
    public let name: String
    /// "30% of grade", or "Points-based" when the course sums points; `nil` for a course whose
    /// grades are not in Canvas (plan 08 §4.4 row 5: Canvas's weights don't describe an external
    /// gradebook).
    public let weightText: String?
}

/// Why the what-if calculator is not offered (plan 08 §4.4 row 6). Each is a whole sentence.
public nonisolated enum WhatIfUnavailable: Equatable, Sendable {
    /// The course's grades are kept outside Canvas (G-4's sentence).
    case notInCanvas
    /// The course has no graded work in Canvas (advisory, homeroom).
    case notGradedInCanvas
    case hiddenTotals
    /// A letters-only course with no grade posted yet.
    case noGradePosted
    case lettersOnly
    /// Every item already has a score.
    case nothingToTry

    /// Plan 08 §4.4 row 6: for a course whose grades are not in Canvas the button stays on screen,
    /// disabled, above the explanation, rather than disappearing without a word.
    public var showsDisabledButton: Bool {
        switch self {
        case .notInCanvas, .notGradedInCanvas: true
        case .hiddenTotals, .noGradePosted, .lettersOnly, .nothingToTry: false
        }
    }

    public var text: String {
        switch self {
        case .notInCanvas: String(localized: L10n.CourseDetail.whatIfNotInCanvas())
        case .notGradedInCanvas: String(localized: L10n.Grades.notGradedDetail())
        case .hiddenTotals: String(localized: L10n.CourseDetail.whatIfHiddenTotals())
        case .noGradePosted: String(localized: L10n.CourseDetail.whatIfNoGradePosted())
        case .lettersOnly: String(localized: L10n.CourseDetail.whatIfLettersOnly())
        case .nothingToTry: String(localized: L10n.CourseDetail.whatIfNothingToTry())
        }
    }
}

/// The what-if sheet's rows (UX-WP-16): work that has no posted score yet, grouped by category.
public nonisolated struct WhatIfItem: Identifiable, Equatable, Sendable {
    public let id: CanvasID<Assignment>
    public let title: String
    public let pointsPossible: Double
    /// "/ 100".
    public let outOfText: String
    public let dueText: String?
}

public nonisolated struct WhatIfGroup: Identifiable, Equatable, Sendable {
    public let id: CanvasID<AssignmentGroup>
    public let name: String
    public let weightText: String
    public let items: [WhatIfItem]
}

/// Everything the what-if sheet needs: the course's `GradeInput` (the domain engine's input, run
/// only through `GradeWork`) and the rows. `nil` on a course that hides totals or shows letters
/// only, where a projected percentage would reveal what the instructor withholds.
public nonisolated struct WhatIfSetup: Equatable, Sendable {
    public let courseName: String
    public let input: GradeInput
    public let groups: [WhatIfGroup]
}

/// Grade distribution (ux-ui.md §3.5: "only if Canvas returns score statistics; otherwise hide it,
/// never random"). The domain model carries no score statistics today, so this is always `nil`
/// and the section never shows.
public nonisolated struct GradeDistribution: Equatable, Sendable {
    public let minimum: Double
    public let mean: Double
    public let maximum: Double
    public let yours: Double
}

/// Course Detail (ux-ui.md §3.7.3, UX-WP-15), built off the main actor.
public nonisolated struct CourseDetailProjection: Identifiable, Equatable, Sendable {
    public let id: CanvasID<Course>
    public let name: String
    public let code: String
    public let paletteIndex: Int
    public let grade: GradeDisplay
    public let health: CourseHealth
    /// The hero as one VoiceOver element.
    public let heroLabel: String
    public let nextDueText: String?
    public let recentGraded: [GradedItem]
    public let weights: [CategoryWeight]
    /// `true` when the course weights its categories; otherwise the shares are of points possible.
    public let weightsAreInstructorSet: Bool
    /// The chart's VoiceOver value: "Exams 50%, Problem Sets 30%, Quizzes 20%".
    public let weightsSummary: String
    public let instructors: [String]
    public let sections: [CourseAssignmentSection]
    public let categories: [CategoryRow]
    /// Whether category percentages may be shown (a course with visible scores).
    public let showsCategoryPercentages: Bool
    /// The Grades segment's source for category percentages: the same input the what-if uses.
    public let gradeInput: GradeInput?
    public let whatIf: WhatIfSetup?
    /// Why there is no what-if, when there is none.
    public let whatIfUnavailable: WhatIfUnavailable?
    /// Plan 08 §4.4 row 5: "Grades for this course aren't in Canvas.", in place of the recent
    /// grades, for a course whose grades are kept outside Canvas.
    public let recentGradesNote: String?
    public let canvasURL: URL?
    public let distribution: GradeDistribution?
}

/// Builds each course's detail from one snapshot (pure; unit-tested).
public nonisolated enum CourseDetailBuilder {
    /// "Recent graded items" on the Overview.
    static let recentGradedLimit = 5

    /// - Parameter gradeAvailability: the projection's `GradeAvailabilityIndex` (plan 08 §4.3);
    ///   `nil` classifies the snapshot at `formatter.now` with no override.
    public static func details(from snapshot: CanvasSnapshot, formatter: ScreenFormatter,
                               gradeAvailability: GradeAvailabilityIndex? = nil)
        -> [CanvasID<Course>: CourseDetailProjection] {
        let availability = gradeAvailability
            ?? GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: formatter.now)
        var details: [CanvasID<Course>: CourseDetailProjection] = [:]
        for (index, course) in snapshot.courses.enumerated() where details[course.id] == nil {
            details[course.id] = detail(course: course, paletteIndex: index, snapshot: snapshot,
                                        availability: availability[course.id], school: availability.school,
                                        formatter: formatter)
        }
        return details
    }

    /// Plan 08 §4.4 rows 5 and 6 (XG-03): for a course whose grades are not in Canvas the hero
    /// shows the dash, the recent grades become one line, the categories keep their names only,
    /// and there is no category chart, no category percentage and no what-if.
    static func detail(course: Course, paletteIndex: Int, snapshot: CanvasSnapshot,
                       availability: GradeAvailability? = nil, school: SchoolGradeSummary = .undetermined,
                       formatter: ScreenFormatter) -> CourseDetailProjection {
        let groups = snapshot.groups[course.id] ?? []
        let periods = snapshot.gradingPeriods[course.id] ?? []
        let grade = GradeDisplay(course: course, availability: availability, school: school, formatter: formatter)
        let health = CourseHealthRules.evaluate(course: course, groups: groups, gradingPeriods: periods,
                                                availability: availability, formatter: formatter).health
        let next = CourseCardBuilder.nextDue(in: groups, now: formatter.now)
        let inCanvas = grade.notInCanvas == nil
        let weights = inCanvas ? categoryWeights(course: course, groups: groups, formatter: formatter) : []
        let lettersOnly = course.gradeVisibility == .lettersOnly
        let percentagesVisible = course.gradeVisibility == .visible && inCanvas
        let input = GradeInput(course: course, groups: groups, gradingPeriods: periods)
        let whatIf = percentagesVisible ? whatIfSetup(course: course, groups: groups, input: input, formatter: formatter) : nil

        var heroWords = [course.name, course.courseCode, grade.spoken]
        if percentagesVisible, course.scores?.currentScore != nil {
            heroWords.append("current grade counts graded work only")
        }
        // The dash's own words already say "Grade not in Canvas".
        if health != .gradeNotInCanvas { heroWords.append(health.label) }

        var keptOutside = false
        if case .keptOutside = grade.notInCanvas { keptOutside = true }

        return CourseDetailProjection(
            id: course.id, name: course.name, code: course.courseCode, paletteIndex: paletteIndex, grade: grade,
            health: health, heroLabel: heroWords.joined(separator: ", "),
            nextDueText: next.map { "\($0.name) · \(formatter.dueText($0.dueAt ?? formatter.now))" },
            recentGraded: keptOutside ? [] : recentGraded(groups: groups, lettersOnly: lettersOnly, formatter: formatter),
            weights: weights, weightsAreInstructorSet: course.appliesGroupWeights,
            weightsSummary: weights.map { "\($0.name) \($0.shareText)" }.joined(separator: ", "),
            instructors: course.teachers.map(\.displayName),
            sections: sections(groups: groups, lettersOnly: lettersOnly, formatter: formatter),
            categories: groups.map { group in
                CategoryRow(id: group.id, name: group.name,
                            weightText: !inCanvas ? nil : course.appliesGroupWeights
                                ? "\(formatter.pointsText(group.weight ?? 0))% of grade" : "Points-based")
            },
            showsCategoryPercentages: percentagesVisible,
            gradeInput: percentagesVisible ? input : nil,
            whatIf: whatIf,
            whatIfUnavailable: whatIf != nil ? nil
                : whatIfUnavailable(course: course, grade: grade, percentagesVisible: percentagesVisible),
            recentGradesNote: keptOutside ? String(localized: L10n.CourseDetail.notInCanvasLine()) : nil,
            canvasURL: course.htmlURL,
            distribution: nil)
    }

    /// The reason the what-if is not offered: the grades are not in Canvas (plan 08 §4.4 row 6),
    /// the instructor hides the totals, the course shows letters only (with or without a posted
    /// grade), or nothing is left without a score.
    static func whatIfUnavailable(course: Course, grade: GradeDisplay, percentagesVisible: Bool) -> WhatIfUnavailable {
        switch grade.notInCanvas {
        case .keptOutside?: return .notInCanvas
        case .notGraded?: return .notGradedInCanvas
        case nil: break
        }
        guard !percentagesVisible else { return .nothingToTry }
        switch course.gradeVisibility {
        case .hiddenTotals: return .hiddenTotals
        case .lettersOnly, .visible: return grade.letter == nil ? .noGradePosted : .lettersOnly
        }
    }

    // MARK: - Category weights

    /// An item that counts toward a grade (the engine's own exclusions: unpublished, not
    /// gradeable, omitted from the final grade, or no points).
    static func counts(_ assignment: Assignment) -> Bool {
        assignment.published && assignment.isGradeable && !assignment.omitFromFinalGrade
            && (assignment.pointsPossible ?? 0) > 0
    }

    /// Weighted courses: each group's `group_weight`. Otherwise each group's share of the points
    /// possible, which is how Canvas sums a points-based course. Empty groups are left out.
    static func categoryWeights(course: Course, groups: [AssignmentGroup], formatter: ScreenFormatter) -> [CategoryWeight] {
        if course.appliesGroupWeights {
            return groups.compactMap { group in
                guard let weight = group.weight, weight > 0 else { return nil }
                return CategoryWeight(id: group.id.rawValue, name: group.name, share: weight / 100,
                                      shareText: formatter.shareText(weight / 100))
            }
        }
        let points = groups.map { group in
            (group, group.assignments.filter(counts).reduce(0) { $0 + ($1.pointsPossible ?? 0) })
        }
        let total = points.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return [] }
        return points.compactMap { group, sum in
            guard sum > 0 else { return nil }
            return CategoryWeight(id: group.id.rawValue, name: group.name, share: sum / total,
                                  shareText: formatter.shareText(sum / total))
        }
    }

    // MARK: - Graded work and assignment sections

    static func scoreText(_ assignment: Assignment, lettersOnly: Bool, formatter: ScreenFormatter) -> String? {
        guard let submission = assignment.submission, submission.postedAt != nil else { return nil }
        if submission.excused { return "Excused" }
        if lettersOnly { return submission.grade }
        guard let score = submission.score else { return submission.grade }
        guard let possible = assignment.pointsPossible, possible > 0 else { return formatter.pointsText(score) }
        return "\(formatter.pointsText(score))/\(formatter.pointsText(possible))"
    }

    static func spokenScore(_ text: String) -> String {
        text.replacingOccurrences(of: "/", with: " out of ")
    }

    static func recentGraded(groups: [AssignmentGroup], lettersOnly: Bool, formatter: ScreenFormatter) -> [GradedItem] {
        var seen = Set<CanvasID<Assignment>>()
        let graded = groups.flatMap(\.assignments).compactMap { assignment -> (Assignment, Date, String)? in
            guard assignment.published, seen.insert(assignment.id).inserted,
                  let posted = assignment.submission?.postedAt,
                  let text = scoreText(assignment, lettersOnly: lettersOnly, formatter: formatter) else { return nil }
            return (assignment, posted, text)
        }
        return graded
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.id < $1.0.id }
            .prefix(recentGradedLimit)
            .map { assignment, posted, text in
                let postedText = "Posted \(formatter.dayText(posted))"
                return GradedItem(id: assignment.id, title: assignment.name, scoreText: text, postedText: postedText,
                                  accessibilityLabel: "\(assignment.name), \(spokenScore(text)), posted \(formatter.dayText(posted, spoken: true))")
            }
    }

    static func sections(groups: [AssignmentGroup], lettersOnly: Bool, formatter: ScreenFormatter) -> [CourseAssignmentSection] {
        let now = formatter.now
        var buckets: [CourseAssignmentSection.Kind: [(row: CourseAssignmentRow, key: Date)]] = [:]
        var seen = Set<CanvasID<Assignment>>()
        for assignment in groups.flatMap(\.assignments) where assignment.published {
            guard seen.insert(assignment.id).inserted else { continue }
            let submission = assignment.submission
            let score = scoreText(assignment, lettersOnly: lettersOnly, formatter: formatter)
            let kind: CourseAssignmentSection.Kind
            let status: WorkStatus?
            if submission?.excused == true {
                kind = .graded
                status = .excused
            } else if score != nil {
                kind = .graded
                status = submission?.late == true ? .late : .graded
            } else if AlertEngine.missingAlert(assignment: assignment, now: now) != nil {
                kind = .missing
                status = .missing
            } else if submission?.isSubmitted == true {
                kind = .submitted
                status = submission?.late == true ? .late : .submitted
            } else if let due = assignment.dueAt, due < now {
                kind = .past
                status = nil
            } else {
                kind = .upcoming
                status = assignment.submissionTypes.allSatisfy { $0 == "none" || $0 == "on_paper" }
                    && !assignment.submissionTypes.isEmpty ? nil : .notSubmitted
            }
            let dueText = assignment.dueAt.map { formatter.dueText($0) }
            var spoken = [assignment.name]
            if let status { spoken.append(status.label) }
            if let score { spoken.append(spokenScore(score)) }
            if let due = assignment.dueAt { spoken.append(formatter.dueText(due, spoken: true)) }
            let row = CourseAssignmentRow(id: assignment.id, title: assignment.name, dueText: dueText, status: status,
                                          scoreText: score, accessibilityLabel: spoken.joined(separator: ", "))
            let key = submission?.postedAt ?? assignment.dueAt ?? .distantFuture
            buckets[kind, default: []].append((row, key))
        }
        let titles: [CourseAssignmentSection.Kind: String] = [
            .upcoming: "Upcoming", .missing: "Missing", .submitted: "Submitted", .graded: "Graded", .past: "Past",
        ]
        return CourseAssignmentSection.Kind.allCases.compactMap { kind in
            guard let entries = buckets[kind], !entries.isEmpty else { return nil }
            // Upcoming and missing: soonest first. Everything else: most recent first.
            let ascending = kind == .upcoming || kind == .missing
            let rows = entries.sorted { a, b in
                a.key != b.key ? (ascending ? a.key < b.key : a.key > b.key) : a.row.id < b.row.id
            }.map(\.row)
            return CourseAssignmentSection(kind: kind, title: titles[kind] ?? kind.rawValue, rows: rows)
        }
    }

    // MARK: - What-if

    /// Work that counts and has no posted score yet: what the student can simulate.
    static func whatIfSetup(course: Course, groups: [AssignmentGroup], input: GradeInput,
                            formatter: ScreenFormatter) -> WhatIfSetup? {
        var seen = Set<CanvasID<Assignment>>()
        let whatIfGroups = groups.compactMap { group -> WhatIfGroup? in
            let items = group.assignments.compactMap { assignment -> WhatIfItem? in
                guard counts(assignment), seen.insert(assignment.id).inserted,
                      let possible = assignment.pointsPossible else { return nil }
                let submission = assignment.submission
                if submission?.excused == true { return nil }
                if submission?.postedAt != nil, submission?.score != nil { return nil }
                return WhatIfItem(id: assignment.id, title: assignment.name, pointsPossible: possible,
                                  outOfText: "/ \(formatter.pointsText(possible))",
                                  dueText: assignment.dueAt.map { formatter.dueText($0) })
            }
            guard !items.isEmpty else { return nil }
            let weightText = course.appliesGroupWeights
                ? "\(formatter.pointsText(group.weight ?? 0))% of grade" : "Points-based"
            return WhatIfGroup(id: group.id, name: group.name, weightText: weightText, items: items)
        }
        guard !whatIfGroups.isEmpty else { return nil }
        return WhatIfSetup(courseName: course.name, input: input, groups: whatIfGroups)
    }
}

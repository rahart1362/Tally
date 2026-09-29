import Foundation
import TallyDomain

/// One card on the Courses tab (ux-ui.md §3.7.2, UX-WP-14), built off the main actor by
/// `HomeProjector`. Every string is final: the view only lays it out.
public nonisolated struct CourseCard: Identifiable, Equatable, Sendable {
    public let id: CanvasID<Course>
    public let name: String
    public let code: String
    /// Index into the categorical course palette: the course's first position in Canvas's order,
    /// so a course keeps its colour when the student reorders the list.
    public let paletteIndex: Int
    /// Canvas's letter (`current_grade`), when the course shows one.
    public let letter: String?
    /// "90.1%", only when the course shows scores (never for hidden totals or letters only).
    public let percentText: String?
    public let health: CourseHealth
    /// "Next: Problem Set 7 · Due Thu at 11:59 PM", or `nil` when nothing is coming up.
    public let nextDueText: String?
    /// One VoiceOver element per card (ux-ui.md §3.7.2): name, code, grade, health, next due.
    public let accessibilityLabel: String

    /// "No grade yet" stands in for a grade the student cannot see (ux-ui.md §3.2.3: never "0%").
    public var gradeText: String { percentText ?? letter ?? "No grade yet" }
}

/// Builds the Courses tab's cards from one snapshot (pure; unit-tested).
public nonisolated enum CourseCardBuilder {
    public static func cards(from snapshot: CanvasSnapshot, formatter: ScreenFormatter) -> [CourseCard] {
        var seen = Set<CanvasID<Course>>()
        return snapshot.courses.enumerated().compactMap { index, course in
            // CS-07: a repeated course ID keeps its first position (List and ForEach need unique IDs).
            guard seen.insert(course.id).inserted else { return nil }
            return card(course: course, paletteIndex: index, snapshot: snapshot, formatter: formatter)
        }
    }

    static func card(course: Course, paletteIndex: Int, snapshot: CanvasSnapshot, formatter: ScreenFormatter) -> CourseCard {
        let groups = snapshot.groups[course.id] ?? []
        let health = CourseHealthRules.evaluate(course: course, groups: groups,
                                                gradingPeriods: snapshot.gradingPeriods[course.id] ?? [],
                                                formatter: formatter)
        let grade = GradeDisplay(course: course, formatter: formatter)
        let next = nextDue(in: groups, now: formatter.now)
        let nextText = next.map { "Next: \($0.name) · \(formatter.dueText($0.dueAt ?? formatter.now))" }

        var spoken = [course.name, course.courseCode, grade.spoken]
        if health.health != .noGradeYet { spoken.append(health.health.label) }
        if let next {
            spoken.append("next \(next.name), \(formatter.dueText(next.dueAt ?? formatter.now, spoken: true))")
        }
        return CourseCard(
            id: course.id, name: course.name, code: course.courseCode, paletteIndex: paletteIndex,
            letter: grade.letter, percentText: grade.percentText, health: health.health, nextDueText: nextText,
            accessibilityLabel: spoken.joined(separator: ", "))
    }

    /// The soonest assignment still to do: published, due now or later, not submitted, graded or
    /// excused. Ties go to Canvas order.
    static func nextDue(in groups: [AssignmentGroup], now: Date) -> Assignment? {
        var best: Assignment?
        for assignment in groups.flatMap(\.assignments) where assignment.published {
            guard let due = assignment.dueAt, due >= now else { continue }
            if let submission = assignment.submission,
               submission.isSubmitted || submission.excused || submission.gradedAt != nil { continue }
            if let current = best?.dueAt, current <= due { continue }
            best = assignment
        }
        return best
    }
}

/// What a course lets the student see of its grade (ux-ui.md §3.2.3 "Grade hidden or not posted"):
/// a percentage only when Canvas shows scores, a letter unless totals are hidden, and otherwise
/// "No grade yet", never 0%.
public nonisolated struct GradeDisplay: Equatable, Sendable {
    public let letter: String?
    public let percentText: String?
    /// "A minus, 90.1 percent", "No grade yet".
    public let spoken: String
    /// Why there is no grade, when there is none.
    public let hiddenReason: String?

    public init(course: Course, formatter: ScreenFormatter) {
        switch course.gradeVisibility {
        case .hiddenTotals:
            letter = nil
            percentText = nil
            hiddenReason = "Your instructor has hidden course totals."
        case .lettersOnly:
            letter = course.scores?.currentGrade
            percentText = nil
            hiddenReason = letter == nil ? "No grade has been posted yet." : nil
        case .visible:
            letter = course.scores?.currentGrade
            percentText = course.scores?.currentScore.map(formatter.percentText)
            hiddenReason = (letter == nil && percentText == nil) ? "No grade has been posted yet." : nil
        }
        var words: [String] = []
        if let letter { words.append(ScreenFormatter.spokenLetter(letter)) }
        if course.gradeVisibility == .visible, let score = course.scores?.currentScore {
            words.append(formatter.spokenPercent(score))
        }
        spoken = words.isEmpty ? "No grade yet" : words.joined(separator: ", ")
    }
}

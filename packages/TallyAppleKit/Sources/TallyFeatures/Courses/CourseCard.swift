import Foundation
import TallyDomain
import TallyStrings

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
    /// Plan 08 §4.4 row 3 (XG-03): set when the course's grades are not in Canvas. The card then
    /// shows "—" with its caption ("Not in Canvas" and an ⓘ button, or "Not graded in Canvas").
    public let notInCanvas: GradeNotInCanvas?

    /// "No grade yet" stands in for a grade the student cannot see (ux-ui.md §3.2.3: never "0%"),
    /// and "—" for a grade kept outside Canvas (plan 08 §4.5).
    public var gradeText: String {
        percentText ?? letter ?? (notInCanvas == nil ? String(localized: L10n.Grades.noGradeYet()) : GradeNotInCanvas.dash)
    }

    /// The ⓘ button's VoiceOver label, "About grades for ENG-10": only for a course whose grades
    /// are kept outside Canvas (a course with no graded work has no bubble and no Tell My School).
    public var infoButtonLabel: String? {
        guard case .keptOutside = notInCanvas else { return nil }
        return String(localized: L10n.Grades.infoButton(courseCode: code))
    }
}

/// Builds the Courses tab's cards from one snapshot (pure; unit-tested).
public nonisolated enum CourseCardBuilder {
    /// - Parameter gradeAvailability: the projection's `GradeAvailabilityIndex` (plan 08 §4.3,
    ///   built once by `HomeProjector`); `nil` classifies the snapshot at `formatter.now` with no
    ///   override.
    public static func cards(from snapshot: CanvasSnapshot, formatter: ScreenFormatter,
                             gradeAvailability: GradeAvailabilityIndex? = nil) -> [CourseCard] {
        let index = gradeAvailability ?? GradeAvailabilityIndex(snapshot: snapshot, overrides: [:], now: formatter.now)
        var seen = Set<CanvasID<Course>>()
        return snapshot.courses.enumerated().compactMap { position, course in
            // CS-07: a repeated course ID keeps its first position (List and ForEach need unique IDs).
            guard seen.insert(course.id).inserted else { return nil }
            return card(course: course, paletteIndex: position, snapshot: snapshot, availability: index[course.id],
                        school: index.school, formatter: formatter)
        }
    }

    static func card(course: Course, paletteIndex: Int, snapshot: CanvasSnapshot, availability: GradeAvailability?,
                     school: SchoolGradeSummary, formatter: ScreenFormatter) -> CourseCard {
        let groups = snapshot.groups[course.id] ?? []
        let health = CourseHealthRules.evaluate(course: course, groups: groups,
                                                gradingPeriods: snapshot.gradingPeriods[course.id] ?? [],
                                                availability: availability, formatter: formatter)
        let grade = GradeDisplay(course: course, availability: availability, school: school, formatter: formatter)
        let next = nextDue(in: groups, now: formatter.now)
        let nextText = next.map {
            String(localized: L10n.Courses.cardNextDue($0.name, formatter.dueText($0.dueAt ?? formatter.now)))
        }

        var spoken = [course.name, course.courseCode, grade.spoken]
        if !health.health.isSaidByTheGrade { spoken.append(health.health.label) }
        if let next {
            spoken.append(String(localized: L10n.Courses.cardNextDueSpoken(
                next.name, formatter.dueText(next.dueAt ?? formatter.now, spoken: true))))
        }
        return CourseCard(
            id: course.id, name: course.name, code: course.courseCode, paletteIndex: paletteIndex,
            letter: grade.letter, percentText: grade.percentText, health: health.health, nextDueText: nextText,
            accessibilityLabel: spoken.joined(separator: ", "), notInCanvas: grade.notInCanvas)
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

/// Plan 08 §4.4 rows 3 and 5 (XG-03): why a course shows "—" instead of a grade.
public nonisolated enum GradeNotInCanvas: Equatable, Sendable {
    /// `.keptOutsideCanvas`: "Not in Canvas", with the ⓘ bubble and Tell My School.
    case keptOutside(GradeInfoScope)
    /// `.notGradedInCanvas` (advisory, homeroom): "Not graded in Canvas", and no Tell My School.
    case notGraded

    /// What stands where the grade goes. VoiceOver never reads it: the grade's element carries
    /// `spoken` instead (plan 08 §4.5).
    public static let dash = "\u{2014}"

    /// The caption under the dash.
    public var caption: String {
        switch self {
        case .keptOutside: String(localized: L10n.Grades.notInCanvasCaption())
        case .notGraded: String(localized: L10n.Grades.notGradedCaption())
        }
    }

    /// What VoiceOver reads for the dash and its caption: "Grade not in Canvas", never "dash".
    public var spoken: String {
        switch self {
        case .keptOutside: String(localized: L10n.Grades.notInCanvasStatus())
        case .notGraded: String(localized: L10n.Grades.notGradedCaption())
        }
    }
}

/// Which body the info bubble shows (plan 08 §4.2 "Per course versus per school"): the
/// course-level text, or the school-level one when no course's grades appear to be in Canvas.
public nonisolated enum GradeInfoScope: Equatable, Sendable {
    case course
    case school

    public init(_ school: SchoolGradeSummary) {
        self = school == .noneInCanvas ? .school : .course
    }
}

/// What a course lets the student see of its grade (ux-ui.md §3.2.3 "Grade hidden or not posted"):
/// a percentage only when Canvas shows scores, a letter unless totals are hidden, and otherwise
/// "No grade yet", never 0%. Plan 08 §4.4 rows 3 and 5: nothing at all, and a dash, for a course
/// whose grades are not in Canvas, whatever Canvas sent.
public nonisolated struct GradeDisplay: Equatable, Sendable {
    public let letter: String?
    public let percentText: String?
    /// "A minus, 90.1 percent", "No grade yet", "Grade not in Canvas".
    public let spoken: String
    /// Why there is no grade, when there is none (and the course's grades are in Canvas).
    public let hiddenReason: String?
    /// Set when the course's grades are not in Canvas.
    public let notInCanvas: GradeNotInCanvas?

    /// - Parameters:
    ///   - availability: the course's state in the projection's index; `nil` classifies the course
    ///     from itself alone (no assignments: rule 2 or "not yet posted").
    ///   - school: the index's school summary, which picks the bubble's wording.
    public init(course: Course, availability: GradeAvailability? = nil, school: SchoolGradeSummary = .undetermined,
                formatter: ScreenFormatter) {
        let availability = availability
            ?? GradeAvailabilityRules.classify(course: course, groups: [], now: formatter.now, override: nil)
        switch availability {
        case .keptOutsideCanvas:
            notInCanvas = .keptOutside(GradeInfoScope(school))
        case .notGradedInCanvas:
            notInCanvas = .notGraded
        case .available, .lettersOnly, .hiddenByInstructor, .notYetPosted:
            notInCanvas = nil
        }
        if let notInCanvas {
            letter = nil
            percentText = nil
            hiddenReason = nil
            spoken = notInCanvas.spoken
            return
        }
        switch course.gradeVisibility {
        case .hiddenTotals:
            letter = nil
            percentText = nil
            hiddenReason = String(localized: L10n.Grades.hiddenByInstructor())
        case .lettersOnly:
            letter = course.scores?.currentGrade
            percentText = nil
            hiddenReason = letter == nil ? String(localized: L10n.Grades.notPostedYet()) : nil
        case .visible:
            letter = course.scores?.currentGrade
            percentText = course.scores?.currentScore.map(formatter.percentText)
            hiddenReason = (letter == nil && percentText == nil) ? String(localized: L10n.Grades.notPostedYet()) : nil
        }
        var words: [String] = []
        if let letter { words.append(ScreenFormatter.spokenLetter(letter)) }
        if course.gradeVisibility == .visible, let score = course.scores?.currentScore {
            words.append(formatter.spokenPercent(score))
        }
        spoken = words.isEmpty ? String(localized: L10n.Grades.noGradeYet()) : words.joined(separator: ", ")
    }
}

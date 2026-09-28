import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyFeatures

/// M3-A: every screen's rows are built off the main actor from real fixture personas (never mock
/// data), in the student's locale. These pin the rules the screens depend on.
enum ScreenFixtures {
    /// The fixtures' capture instant (2026-09-28T13:00:00Z, a Monday), so "now" matches the data.
    static let anchor = Date(timeIntervalSince1970: 1_790_600_400)

    static func formatter(now: Date = anchor, locale: String = "en_US") -> ScreenFormatter {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
        calendar.locale = Locale(identifier: locale)
        return ScreenFormatter(now: now, calendar: calendar, locale: Locale(identifier: locale))
    }

    static func projections(_ persona: String, now: Date = anchor) async throws -> (CanvasSnapshot, ScreenProjections) {
        let snapshot = try await PersonaSnapshotHarness.fetchSnapshot(persona: persona, now: now)
        return (snapshot, ScreenProjections.build(from: snapshot, formatter: formatter(now: now)))
    }
}

@Suite("M3-A projections: Courses (UX-WP-14)")
struct CourseCardProjectionTests {
    @Test("flagship: one card per course, in Canvas order, with grade, health and next due")
    func flagshipCards() async throws {
        let (snapshot, screens) = try await ScreenFixtures.projections("flagship")
        let cards = screens.courseCards
        #expect(cards.map(\.id) == snapshot.courses.map(\.id))
        #expect(cards.count == 5)
        let math = try #require(cards.first { $0.code == "MATH 122" })
        #expect(math.letter == "A-")
        #expect(math.percentText == "90.1%")
        let problemSet7 = try #require(snapshot.groups[math.id]?.flatMap(\.assignments).first { $0.name == "Problem Set 7" })
        let formatter = ScreenFixtures.formatter()
        #expect(math.nextDueText == "Next: Problem Set 7 · Due Thu at \(formatter.timeText(try #require(problemSet7.dueAt)))")
        // One open missing item (Worksheet 3) and 0.1 points above the 90% cutoff.
        #expect(math.health == .needsAttention)
        #expect(math.accessibilityLabel.hasPrefix("Calculus II, MATH 122, A minus, 90.1 percent, Needs attention"))
    }

    @Test("A11Y-06: every card's VoiceOver label carries the course code and the health words")
    func cardLabelsCarryCodeAndStatus() async throws {
        for persona in ["flagship", "grading-periods", "finals"] {
            let (_, screens) = try await ScreenFixtures.projections(persona)
            for card in screens.courseCards {
                #expect(card.accessibilityLabel.contains(card.code), "\(card.accessibilityLabel)")
                let status = card.health == .noGradeYet ? "No grade yet" : card.health.label
                #expect(card.accessibilityLabel.contains(status), "\(card.accessibilityLabel)")
            }
        }
    }

    @Test("a course that hides totals shows no grade, never 0%, and no percentage anywhere")
    func hiddenTotalsShowNoGrade() async throws {
        let (_, screens) = try await ScreenFixtures.projections("grading-periods")
        let chemistry = try #require(screens.courseCards.first { $0.code == "CHEM-H" })
        #expect(chemistry.letter == nil)
        #expect(chemistry.percentText == nil)
        #expect(chemistry.gradeText == "No grade yet")
        #expect(chemistry.health == .noGradeYet)
        let detail = try #require(screens.courseDetails[chemistry.id])
        #expect(detail.grade.hiddenReason == "Your instructor has hidden course totals.")
        #expect(detail.whatIf == nil, "a projection would reveal the totals the instructor hides")
        #expect(detail.gradeInput == nil)
        #expect(!detail.showsCategoryPercentages)
    }

    @Test("hidden totals stay hidden even when Canvas sends a score and a letter", arguments: [
        (GradeVisibility.hiddenTotals, nil as String?, nil as String?),
        (.lettersOnly, "B+", nil),
        (.visible, "B+", "88.6%"),
    ])
    func visibilityDecidesWhatShows(_ visibility: GradeVisibility, _ letter: String?, _ percent: String?) {
        let course = Course(
            id: "1", name: "Chemistry", courseCode: "CHEM 1", term: nil, teachers: [], timeZone: nil,
            appliesGroupWeights: false, hasGradingPeriods: false, currentGradingPeriodID: nil, gradeVisibility: visibility,
            scores: ComputedScores(currentScore: 88.6, finalScore: 70, currentGrade: "B+", finalGrade: "C-"),
            currentPeriodScores: nil, htmlURL: nil)
        let grade = GradeDisplay(course: course, formatter: ScreenFixtures.formatter())
        #expect(grade.letter == letter)
        #expect(grade.percentText == percent)
        if visibility == .hiddenTotals {
            #expect(grade.spoken == "No grade yet")
            #expect(!grade.spoken.contains("88"))
        }
    }

    @Test("a pass/fail course is never 'near a cutoff' of a letter scale")
    func passFailHasNoLetterCutoffs() async throws {
        let (_, screens) = try await ScreenFixtures.projections("grading-periods")
        let pe = try #require(screens.courseCards.first { $0.code == "PE-9" })
        #expect(pe.letter == "Pass")
        #expect(pe.health == .onTrack)
    }

    @Test("health: two open missing items worth 2% or more make a course at risk; one needs attention")
    func healthFromMissingWork() async throws {
        let snapshot = try await PersonaSnapshotHarness.fetchSnapshot(persona: "flagship", now: ScreenFixtures.anchor)
        let formatter = ScreenFixtures.formatter()
        let math = try #require(snapshot.courses.first { $0.courseCode == "MATH 122" })
        let groups = snapshot.groups[math.id] ?? []
        let one = CourseHealthRules.evaluate(course: math, groups: groups, gradingPeriods: [], formatter: formatter)
        #expect(one.health == .needsAttention)
        #expect(one.openMissingCount == 1)
        #expect(one.reasons.first == "1 missing item is still accepted")

        // Two more items, each worth at least 2% of the course, moved into the past and flagged missing.
        let bumped = groups.map { group in
            AssignmentGroup(id: group.id, name: group.name, position: group.position, weight: group.weight,
                            rules: group.rules, assignments: group.assignments.map { assignment in
                guard ["Problem Set 8", "Quiz 5"].contains(assignment.name),
                      let submission = assignment.submission else { return assignment }
                let missing = Submission(score: nil, grade: nil, submittedAt: nil, gradedAt: nil, postedAt: nil,
                                         excused: false, missing: true, late: false, workflowState: "unsubmitted",
                                         id: submission.id)
                return Assignment(id: assignment.id, courseID: assignment.courseID, groupID: assignment.groupID,
                                  name: assignment.name, dueAt: ScreenFixtures.anchor.addingTimeInterval(-3600),
                                  lockAt: nil, pointsPossible: assignment.pointsPossible, gradingType: assignment.gradingType,
                                  omitFromFinalGrade: false, htmlURL: nil, submission: missing,
                                  submissionTypes: assignment.submissionTypes)
            })
        }
        let two = CourseHealthRules.evaluate(course: math, groups: bumped, gradingPeriods: [], formatter: formatter)
        #expect(two.health == .atRisk)
        #expect(two.openMissingCount == 3)
        #expect(two.reasons == ["3 missing items are still accepted"])
    }
}

@Suite("M3-A: the student's course order (UX-WP-14)")
struct CourseOrderTests {
    private static let ids: [CanvasID<Course>] = ["a", "b", "c", "d"]

    @Test("moving matches SwiftUI's onMove semantics", arguments: [
        ([0], 2, ["b", "a", "c", "d"]),
        ([3], 0, ["d", "a", "b", "c"]),
        ([1, 2], 4, ["a", "d", "b", "c"]),
        ([0], 4, ["b", "c", "d", "a"]),
        ([2], 2, ["a", "b", "c", "d"]),
    ] as [([Int], Int, [String])])
    func moving(_ source: [Int], _ destination: Int, _ expected: [String]) {
        let moved = CourseOrder.moving(Self.ids, fromOffsets: IndexSet(source), toOffset: destination)
        #expect(moved.map(\.rawValue) == expected)
    }

    @Test("arrange puts ordered courses first, keeps new ones in Canvas order after them, ignores gone ones")
    func arrange() async throws {
        let (_, screens) = try await ScreenFixtures.projections("flagship")
        let cards = screens.courseCards
        let order = [cards[3].id, "gone", cards[1].id]
        let arranged = CourseOrder.arrange(cards, by: order)
        #expect(arranged.map(\.id) == [cards[3].id, cards[1].id, cards[0].id, cards[2].id, cards[4].id])
        #expect(CourseOrder.arrange(cards, by: []).map(\.id) == cards.map(\.id))
    }
}

@Suite("M3-A projections: To-Do (UX-WP-18)")
struct ToDoProjectionTests {
    @Test("flagship: missing work comes first, still accepted, with its status words and course code")
    func missingFirst() async throws {
        let (_, screens) = try await ScreenFixtures.projections("flagship")
        let sections = screens.toDo.sections
        #expect(sections.map(\.kind) == [.missing, .thisWeek, .later])
        #expect(sections.first?.title == "Missing & overdue")
        let missing = try #require(sections.first).byDueDate
        #expect(Set(missing.map(\.title)) == ["Worksheet 3: Integration by Parts", "Primary Source Analysis 3"])
        for item in missing {
            #expect(item.status == .missing)
            #expect(item.lateNote == "Still accepted")
            #expect(item.needsCanvasSubmission)
        }
        #expect(screens.toDo.missingCount == 2)
    }

    @Test("A11Y-06: every row's label carries its course code and status words")
    func rowLabels() async throws {
        let (_, screens) = try await ScreenFixtures.projections("flagship")
        let items = screens.toDo.sections.flatMap(\.byDueDate)
        #expect(!items.isEmpty)
        for item in items {
            #expect(item.accessibilityLabel.contains(item.courseCode))
            if let status = item.status { #expect(item.accessibilityLabel.contains(status.label)) }
        }
    }

    @Test("every sort order holds the same rows; due date ascending, priority descending by band")
    func sortOrders() async throws {
        let (_, screens) = try await ScreenFixtures.projections("flagship")
        for section in screens.toDo.sections {
            let ids = Set(section.byDueDate.map(\.id))
            #expect(Set(section.byPriority.map(\.id)) == ids)
            #expect(Set(section.byCourse.map(\.id)) == ids)
            #expect(section.byDueDate.count == ids.count, "a row appears twice")
        }
        let week = try #require(screens.toDo.sections.first { $0.kind == .thisWeek })
        #expect(week.byDueDate.first?.title == "Quiz 5: Cellular Respiration")
        let bands = week.byPriority.map(\.band)
        let rank: [PriorityScore.Band: Int] = [.high: 0, .medium: 1, .low: 2]
        #expect(bands.map { rank[$0] ?? 3 } == bands.map { rank[$0] ?? 3 }.sorted())
    }

    @Test("submitted, graded and excused work is never to-do; in-class work has no online status")
    func notToDo() async throws {
        let (snapshot, screens) = try await ScreenFixtures.projections("flagship")
        let listed = Set(screens.toDo.sections.flatMap(\.byDueDate).map(\.id))
        for group in snapshot.groups.values.flatMap({ $0 }) {
            for assignment in group.assignments {
                guard let submission = assignment.submission else { continue }
                if submission.isSubmitted || submission.excused || submission.gradedAt != nil {
                    #expect(!listed.contains(assignment.id), "\(assignment.name) is done but listed")
                }
            }
        }
        let participation = try #require(screens.toDo.sections.flatMap(\.byDueDate).first { $0.title == "Participation: September" })
        #expect(participation.status == nil)
        #expect(!participation.needsCanvasSubmission)
    }

    @Test("a closed missing item says so and is not counted as still open")
    func closedMissing() throws {
        let formatter = ScreenFixtures.formatter()
        let past = ScreenFixtures.anchor.addingTimeInterval(-7200)
        let submission = Submission(score: nil, grade: nil, submittedAt: nil, gradedAt: nil, postedAt: nil,
                                    excused: false, missing: true, late: false, workflowState: "unsubmitted")
        let closed = Assignment(id: "9", courseID: "1", groupID: "1", name: "Lab", dueAt: past.addingTimeInterval(-3600),
                                lockAt: past, pointsPossible: 10, gradingType: .points, omitFromFinalGrade: false,
                                htmlURL: nil, submission: submission, submissionTypes: ["online_upload"])
        let placement = try #require(ToDoBuilder.placement(of: closed, now: formatter.now))
        #expect(placement.section == .missing)
        #expect(placement.late == .closed)
        let row = ToDoBuilder.row(assignment: closed, course: Course(
            id: "1", name: "Chemistry", courseCode: "CHEM 1", term: nil, teachers: [], timeZone: nil,
            appliesGroupWeights: false, hasGradingPeriods: false, currentGradingPeriodID: nil, gradeVisibility: .visible,
            scores: nil, currentPeriodScores: nil, htmlURL: nil), paletteIndex: 0, placement: placement, band: .high,
            formatter: formatter)
        #expect(row.lateNote == "Closed — talk to your instructor")
    }
}

@Suite("M3-A projections: Calendar (UX-WP-17)")
struct CalendarProjectionTests {
    @Test("flagship: a 7-day strip for this week, 14 agenda days, today marked, classes with time ranges")
    func weekAndAgenda() async throws {
        let (_, screens) = try await ScreenFixtures.projections("flagship")
        let calendar = screens.calendar
        #expect(calendar.week.count == 7)
        #expect(calendar.days.count == 14)
        #expect(calendar.monthTitle == "September")
        let today = try #require(calendar.days.first { $0.isToday })
        #expect(calendar.todayID == today.id)
        #expect(today.heading == "Today · Mon, Sep 28")
        #expect(today.stripLabel.contains("today"))
        let lecture = try #require(today.items.first { $0.title == "Calculus II Lecture" })
        #expect(lecture.kind == .classMeeting)
        let formatter = ScreenFixtures.formatter()
        let start = ScreenFixtures.anchor.addingTimeInterval(2 * 3600) // 10:00 AM in Chicago
        #expect(lecture.timeText == "\(formatter.timeText(start)) – \(formatter.timeText(start.addingTimeInterval(50 * 60)))")
        #expect(lecture.location == "Sage Hall 210")
        #expect(lecture.courseCode == "MATH 122")
        #expect(calendar.week.map(\.dotCount).allSatisfy { (0...3).contains($0) })
    }

    @Test("the AX day pager steps through the agenda from today and stops at either end")
    func dayPager() async throws {
        let (_, screens) = try await ScreenFixtures.projections("flagship")
        let calendar = screens.calendar
        let today = try #require(calendar.day(from: nil, offset: 0))
        #expect(today.isToday)
        #expect(calendar.day(from: today.id, offset: 1)?.id == calendar.days.first { $0.id > today.id }?.id)
        #expect(calendar.day(from: today.id, offset: -1)?.id == calendar.days.last { $0.id < today.id }?.id)
        let first = try #require(calendar.days.first)
        let last = try #require(calendar.days.last)
        #expect(calendar.day(from: first.id, offset: -1) == nil)
        #expect(calendar.day(from: last.id, offset: 1) == nil)
        #expect(calendar.day(from: first.id, offset: calendar.days.count - 1)?.id == last.id)
        #expect(CalendarProjection.empty.day(from: nil, offset: 0) == nil)
    }

    @Test("R6: the student's own feed as a webcal:// link")
    func subscribeLink() async throws {
        let (_, screens) = try await ScreenFixtures.projections("flagship")
        let url = try #require(screens.calendar.subscribeURL)
        #expect(url.scheme == "webcal")
        #expect(url.host == "canvas.northfield.example")
        #expect(url.path.hasSuffix(".ics"))
        #expect(CalendarBuilder.webcal(try #require(URL(string: "ftp://x.example/a.ics"))) == nil)
    }

    @Test("finals: overlapping exams in two courses carry icon-ready conflict text; a course's own exam does not clash with itself")
    func conflicts() async throws {
        let (_, screens) = try await ScreenFixtures.projections("finals")
        let items = screens.calendar.days.flatMap(\.items)
        let accounting = try #require(items.first { $0.title == "ACCT 201 Final Exam" })
        #expect(accounting.conflictText == "Overlaps with CHEM 110 Final Exam")
        #expect(accounting.isExam)
        #expect(accounting.accessibilityLabel.contains("conflict: Overlaps with CHEM 110 Final Exam"))
        let statistics = try #require(items.first { $0.title == "STAT 150 Final Exam" })
        #expect(statistics.conflictText == nil, "STAT 150's exam session and its own exam assignment are one commitment")
    }

    @Test("a due item's block ends at the deadline; Add to Calendar gets the same times")
    func dueBlocks() async throws {
        let (_, screens) = try await ScreenFixtures.projections("flagship")
        let due = try #require(screens.calendar.days.flatMap(\.items).first { $0.kind == .due && $0.title == "Problem Set 7" })
        #expect(due.timeText == "Due \(ScreenFixtures.formatter().timeText(due.draft.end))")
        #expect(due.draft.end.timeIntervalSince(due.draft.start) == TimeInterval(CalendarBuilder.dueMarkerMinutes * 60))
        #expect(due.draft.title == "MATH 122: Problem Set 7")
        #expect(due.startMinute + due.durationMinutes <= 24 * 60)
    }

    @Test("exam words are whole words, any case", arguments: [
        ("Midterm Exam", true), ("Final Persuasive Speech", true), ("Unit 2 Test", true),
        ("Testing hypotheses", false), ("Examples of chirality", false), ("Lab 6", false),
    ])
    func examDetection(_ title: String, _ isExam: Bool) {
        #expect(CalendarBuilder.isExam(title) == isExam)
    }
}

@Suite("M3-A projections: Course Detail (UX-WP-15)")
struct CourseDetailProjectionTests {
    @Test("MATH 122: instructor weights, sections, what-if rows, and no distribution without statistics")
    func math() async throws {
        let (snapshot, screens) = try await ScreenFixtures.projections("flagship")
        let math = try #require(snapshot.courses.first { $0.courseCode == "MATH 122" })
        let detail = try #require(screens.courseDetails[math.id])
        #expect(detail.weights.map(\.name) == ["Problem Sets", "Quizzes", "Exams"])
        #expect(detail.weights.map(\.shareText) == ["30%", "20%", "50%"])
        #expect(detail.weightsAreInstructorSet)
        #expect(detail.weightsSummary == "Problem Sets 30%, Quizzes 20%, Exams 50%")
        #expect(detail.sections.map(\.kind) == [.upcoming, .missing, .graded])
        #expect(detail.recentGraded.first?.scoreText == "92/100")
        #expect(detail.recentGraded.first?.accessibilityLabel.contains("92 out of 100") == true)
        #expect(detail.instructors == ["Casey Linden", "Quinn Harlow"])
        #expect(detail.distribution == nil)
        let whatIf = try #require(detail.whatIf)
        #expect(whatIf.groups.map(\.name) == ["Problem Sets", "Quizzes", "Exams"])
        #expect(whatIf.groups.allSatisfy { !$0.items.isEmpty })
        #expect(detail.gradeInput == whatIf.input)
    }

    @Test("a points-based course's shares are of points possible and add up to the whole")
    func pointsBased() async throws {
        let (snapshot, screens) = try await ScreenFixtures.projections("flagship")
        let psychology = try #require(snapshot.courses.first { $0.courseCode == "PSY 101" })
        let detail = try #require(screens.courseDetails[psychology.id])
        #expect(!detail.weightsAreInstructorSet)
        #expect(abs(detail.weights.reduce(0) { $0 + $1.share } - 1) < 0.000_001)
        #expect(detail.categories.allSatisfy { $0.weightText == "Points-based" })
    }

    @Test("no course in any persona carries a distribution (the domain has no score statistics)")
    func distributionAlwaysHidden() async throws {
        for persona in ["flagship", "grading-periods", "finals", "large"] {
            let (_, screens) = try await ScreenFixtures.projections(persona)
            #expect(screens.courseDetails.values.allSatisfy { $0.distribution == nil })
        }
    }
}

@Suite("M3-A projections: Insights (UX-WP-19, R13)")
struct InsightsProjectionTests {
    @Test("flagship: on-time rate, streak, courses needing a look with reasons, heavy stretches")
    func flagship() async throws {
        let (_, screens) = try await ScreenFixtures.projections("flagship")
        let insights = screens.insights
        let completion = try #require(insights.completion)
        #expect(completion.headline == "88% on time this term")
        #expect(completion.detail == "36 of 41 past-due assignments were submitted on time.")
        #expect(insights.streak.headline == "1-day streak")
        #expect(insights.risks.map(\.code) == ["BIO 101", "MATH 122", "PSY 101", "HIST 210"])
        #expect(insights.risks.allSatisfy { !$0.reasons.isEmpty })
        #expect(insights.heavyStretches.first?.headline == "4 items due Sep 29–Sep 30")
    }

    @Test("the category breakdown adds up to the whole and names at most 5 categories plus Other")
    func categoryShares() async throws {
        for persona in ["flagship", "finals", "grading-periods"] {
            let (_, screens) = try await ScreenFixtures.projections(persona)
            let shares = screens.insights.categoryShares
            #expect(abs(shares.reduce(0) { $0 + $1.share } - 1) < 0.000_001, "\(persona)")
            #expect(shares.count <= InsightsBuilder.categoryLimit + 1)
            #expect(!screens.insights.categorySummary.isEmpty)
        }
    }

    @Test("an empty account has no insights to fabricate")
    func empty() async throws {
        let (_, screens) = try await ScreenFixtures.projections("empty")
        #expect(screens.insights.completion == nil)
        #expect(screens.insights.risks.isEmpty)
        #expect(screens.insights.categoryShares.isEmpty)
        #expect(screens.insights.trendInput.courses.isEmpty)
        #expect(screens.courseCards.isEmpty)
        #expect(screens.toDo.sections.isEmpty)
    }
}

@Suite("M3-A: Open in Canvas (R20)")
struct CanvasLinkTests {
    @Test("an https Canvas URL becomes the Canvas Student app's canvas-courses:// URL, path and query kept")
    func appURL() throws {
        let web = try #require(URL(string: "https://canvas.northfield.example/courses/51842/assignments/1204405?module_item_id=7"))
        let app = try #require(CanvasLink.appURL(for: web))
        #expect(app.absoluteString == "canvas-courses://canvas.northfield.example/courses/51842/assignments/1204405?module_item_id=7")
    }

    @Test("anything but an http(s) URL with a host has no app URL (the web fallback is used)", arguments: [
        "mailto:someone@northfield.example", "canvas-courses://x.example/a", "file:///tmp/a", "https:///no-host",
    ])
    func noAppURL(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(CanvasLink.appURL(for: url) == nil)
    }
}

@Suite("M3-A: dates and numbers in the student's locale")
struct ScreenFormatterTests {
    @Test("relative due text")
    func dueText() {
        let formatter = ScreenFixtures.formatter()
        let hour: TimeInterval = 3600
        let anchor = ScreenFixtures.anchor // 8:00 AM Monday in Chicago
        // The time itself comes from the locale (ICU may use a narrow no-break space before "AM").
        let ten = formatter.timeText(anchor.addingTimeInterval(2 * hour))
        let eight = formatter.timeText(anchor)
        #expect(ten.hasPrefix("10:00") && ten.hasSuffix("AM"))
        #expect(formatter.dueText(anchor.addingTimeInterval(2 * hour)) == "Due today at \(ten)")
        #expect(formatter.dueText(anchor.addingTimeInterval(24 * hour)) == "Due tomorrow at \(eight)")
        #expect(formatter.dueText(anchor.addingTimeInterval(72 * hour)) == "Due Thu at \(eight)")
        #expect(formatter.dueText(anchor.addingTimeInterval(72 * hour), spoken: true) == "Due Thursday at \(eight)")
        #expect(formatter.dueText(anchor.addingTimeInterval(10 * 24 * hour)) == "Due Oct 8")
        #expect(formatter.dueText(anchor.addingTimeInterval(-3 * 24 * hour)) == "Was due Fri")
    }

    @Test("letters are spoken, not spelled", arguments: [("A-", "A minus"), ("B+", "B plus"), ("C", "C"), ("Pass", "Pass")])
    func spokenLetters(_ letter: String, _ spoken: String) {
        #expect(ScreenFormatter.spokenLetter(letter) == spoken)
    }

    @Test("percentages follow the locale")
    func percents() {
        #expect(ScreenFixtures.formatter().percentText(90.1) == "90.1%")
        #expect(ScreenFixtures.formatter(locale: "de_DE").percentText(90.1) == "90,1%")
    }
}

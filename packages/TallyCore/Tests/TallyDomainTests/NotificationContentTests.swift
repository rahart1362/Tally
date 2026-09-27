import Foundation
import Testing
import TallyTestSupport
@testable import TallyDomain

@Suite("NotificationContent: R10 — never a grade value, Hide course names")
struct NotificationContentTests {
    // MARK: - Content-table spot checks (§3.6)

    @Test func dueReminderMatchesTheContentTable() {
        let r = NotificationContent.due(
            assignmentTitle: "Lab Report 4", courseCode: "BIO 101", dueTimeText: "today at 6:00 PM",
            isFinalReminder: false, hideCourseNames: false)
        #expect(r.title == "Lab Report 4 · BIO 101")
        #expect(r.body == "Due today at 6:00 PM.")
    }

    @Test func finalReminderUsesTheConditionalPhrasing() {
        let r = NotificationContent.due(
            assignmentTitle: "Lab Report 4", courseCode: "BIO 101", dueTimeText: "in 1 hour",
            isFinalReminder: true, hideCourseNames: false)
        #expect(r.body == "Due in 1 hour, if you haven't submitted yet.")
    }

    @Test func missingFollowupMatchesTheContentTable() {
        let r = NotificationContent.missingFollowup(
            assignmentTitle: "Problem Set 6", courseCode: "MATH 122", stillAcceptedUntilText: "Fri 11:59 PM", hideCourseNames: false)
        #expect(r.title == "Problem Set 6 · MATH 122")
        #expect(r.body == "Still accepted until Fri 11:59 PM.")
    }

    @Test func gradePostedNeverIncludesTheScore() {
        let r = NotificationContent.gradePosted(courseCode: "Calculus II", hideCourseNames: false)
        #expect(r.title == "New grade posted")
        #expect(r.body == "Calculus II")
    }

    @Test func belowGoalNeverIncludesTheScoreOrGoal() {
        let r = NotificationContent.belowGoal(courseCode: "Calculus II", hideCourseNames: false)
        #expect(r.title == "Calculus II needs attention")
        #expect(r.body == "Open Tally to see your standing.")
    }

    @Test func sentinelMatchesTheContentTable() {
        let r = NotificationContent.sentinel(lastSuccessText: "Tue 2:14 PM")
        #expect(r.title == "Tally hasn't refreshed since Tue 2:14 PM")
        #expect(r.body == "Open Tally to update your reminders.")
    }

    @Test func digestMatchesTheContentTable() {
        let r = NotificationContent.eveningDigest(dueCount: 2, firstItemTitle: "Lab Report 4", hideCourseNames: false)
        #expect(r.title == "Tomorrow")
        #expect(r.body == "2 due · Lab Report 4 first")
    }

    // MARK: - Hide course names (R10) hides BOTH course and assignment title

    @Test func hideCourseNamesRedactsTheDueReminder() {
        let r = NotificationContent.due(
            assignmentTitle: "Lab Report 4", courseCode: "BIO 101", dueTimeText: "today", isFinalReminder: false, hideCourseNames: true)
        #expect(r.title == "An assignment")
        #expect(!r.title.contains("Lab Report"))
        #expect(!r.body.contains("BIO"))
    }

    @Test func hideCourseNamesRedactsGradePostedAndBelowGoal() {
        #expect(NotificationContent.gradePosted(courseCode: "Calculus II", hideCourseNames: true).body == "a course")
        #expect(NotificationContent.belowGoal(courseCode: "Calculus II", hideCourseNames: true).title == "a course needs attention")
    }

    @Test func hideCourseNamesRedactsTheDigestsFirstItemTitle() {
        let r = NotificationContent.eveningDigest(dueCount: 1, firstItemTitle: "Lab Report 4", hideCourseNames: true)
        #expect(!r.body.contains("Lab Report"))
        #expect(r.body.contains("An assignment"))
    }

    @Test func weekAheadNeverNamesACourseOrItem() {
        let r = NotificationContent.weekAhead(dueCount: 7, busiestDayText: "Thursday")
        #expect(r.title == "This week")
        #expect(r.body == "7 due · busiest Thursday")
    }

    // MARK: - Property test: over every fixture persona, no notification text
    // contains a score or percentage (WP-D02 acceptance criterion).

    @Test(arguments: Fixtures.personas)
    func noFixturePersonaProducesAScoreOrPercentageInNotificationText(_ persona: String) throws {
        let courses = try GradeFixtures.courses(persona: persona)
        var checked = 0
        for course in courses {
            for group in course.groups {
                for assignment in group.assignments {
                    for hideCourseNames in [false, true] {
                        let due = NotificationContent.due(
                            assignmentTitle: assignment.name, courseCode: course.course.courseCode,
                            dueTimeText: "today at 6:00 PM", isFinalReminder: false, hideCourseNames: hideCourseNames)
                        let final = NotificationContent.due(
                            assignmentTitle: assignment.name, courseCode: course.course.courseCode,
                            dueTimeText: "in 1 hour", isFinalReminder: true, hideCourseNames: hideCourseNames)
                        let followup = NotificationContent.missingFollowup(
                            assignmentTitle: assignment.name, courseCode: course.course.courseCode,
                            stillAcceptedUntilText: "Fri 11:59 PM", hideCourseNames: hideCourseNames)
                        let exam = NotificationContent.examReminder(
                            assignmentTitle: assignment.name, courseCode: course.course.courseCode,
                            dueTimeText: "Wed 9:00 AM", hideCourseNames: hideCourseNames)
                        let digest = NotificationContent.eveningDigest(
                            dueCount: 3, firstItemTitle: assignment.name, hideCourseNames: hideCourseNames)
                        for rendered in [due, final, followup, exam, digest] {
                            assertNoScoreOrPercentage(rendered, persona: persona, assignment: assignment.name)
                        }
                        checked += 1

                        if hideCourseNames {
                            #expect(!due.title.contains(assignment.name), "\(persona): title leaked the assignment name under Hide course names")
                            #expect(!due.body.contains(course.course.courseCode), "\(persona): body leaked the course code under Hide course names")
                        }
                    }
                }
            }
            for hideCourseNames in [false, true] {
                let posted = NotificationContent.gradePosted(courseCode: course.course.courseCode, hideCourseNames: hideCourseNames)
                let below = NotificationContent.belowGoal(courseCode: course.course.courseCode, hideCourseNames: hideCourseNames)
                assertNoScoreOrPercentage(posted, persona: persona, assignment: course.course.courseCode)
                assertNoScoreOrPercentage(below, persona: persona, assignment: course.course.courseCode)
            }
        }
        // "empty" (Morgan Sample) has no enrollments at all (fixtures/canvas
        // README): zero assignments is the correct, verified state there,
        // not a test-setup bug.
        if persona != "empty" {
            #expect(checked > 0, "\(persona): expected at least one assignment to check")
        }
    }

    /// The definitive R10 marker is a percent sign; NotificationContent also
    /// structurally cannot emit a score, since none of its functions accept
    /// one (there is no score/grade parameter anywhere in its API).
    private func assertNoScoreOrPercentage(_ rendered: NotificationContent.Rendered, persona: String, assignment: String) {
        #expect(!rendered.title.contains("%"), "\(persona)/\(assignment): title contains '%': \(rendered.title)")
        #expect(!rendered.body.contains("%"), "\(persona)/\(assignment): body contains '%': \(rendered.body)")
    }
}

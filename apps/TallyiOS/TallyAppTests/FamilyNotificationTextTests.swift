import Foundation
import Testing
import TallyDomain
import TallyStrings

/// SEC2-08 (owner ruling 2026-10-23): the parent's below-goal notification hides the course by
/// default, the same way SEC1-19 already hides it for the student's own below-goal notification.
/// `FamilyNotificationText.render` had no unit test at all before this fix — TallyAppleKit's
/// family renderer is otherwise only exercised end to end through `FamilyReminderWiringTests`,
/// which scans rendered words for a leaked grade or percentage but never for a course code, so it
/// would not have caught this.
@Suite("FamilyNotificationText: SEC2-08's below-goal course is always hidden")
struct FamilyNotificationTextTests {
    private let seenAt = Date(timeIntervalSince1970: 1_790_600_400)
    private let chicago = TimeZone(identifier: "America/Chicago") ?? .gmt

    @Test("the course code never appears, with the student named")
    func belowGoalHidesTheCourseWithTheStudentNamed() {
        let rendered = FamilyNotificationText.render(.belowGoal(student: .named("Maya"), courseCode: "BIO 101"),
                                                      seenAt: seenAt, timeZone: chicago, weekdayNamingDays: 6)
        #expect(!rendered.title.contains("BIO 101"), "SEC2-08: the course must never be named: \(rendered.title)")
        #expect(rendered.title == "Maya has a course that needs attention")
    }

    @Test("Hide Student Names still applies on top of the hidden course")
    func belowGoalHidesBothTheStudentAndTheCourse() {
        let rendered = FamilyNotificationText.render(.belowGoal(student: .hidden, courseCode: "BIO 101"),
                                                      seenAt: seenAt, timeZone: chicago, weekdayNamingDays: 6)
        #expect(!rendered.title.contains("BIO 101"), "SEC2-08: the course must never be named: \(rendered.title)")
        #expect(rendered.title == "Your student has a course that needs attention")
    }
}

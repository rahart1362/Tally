import Foundation

/// WP-D02: builds notification title/body text that **never emits a grade
/// value** (PMO R10) — structurally, not just by convention: no function
/// here accepts a score, percentage or letter grade parameter at all, so
/// there is nothing for it to leak. Date/time formatting is the app layer's
/// job (locale-aware); every "…Text" parameter here is an already-formatted
/// opaque string, so this type never touches a raw `Date` either.
///
/// Every builder honours "Hide course names" (R10): course names/codes
/// become "a course" and assignment titles become "An assignment" (the
/// toggle hides both, per the UX review's content table, despite its name).
public enum NotificationContent {
    public struct Rendered: Sendable, Equatable {
        public let title: String
        public let body: String
        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }

    private static func subjectTitle(_ assignmentTitle: String, courseCode: String, hideCourseNames: Bool) -> String {
        hideCourseNames ? "An assignment" : "\(assignmentTitle) · \(courseCode)"
    }

    private static func courseLabel(_ courseCode: String, hideCourseNames: Bool) -> String {
        hideCourseNames ? "a course" : courseCode
    }

    private static func itemLabel(_ title: String, hideCourseNames: Bool) -> String {
        hideCourseNames ? "An assignment" : title
    }

    /// The T-24h/T-1h due reminder. The final (soonest) reminder uses the
    /// "conditional follow-up" phrasing, since Tally cannot know at schedule
    /// time whether the student has since submitted (§3.6).
    public static func due(
        assignmentTitle: String, courseCode: String, dueTimeText: String, isFinalReminder: Bool, hideCourseNames: Bool
    ) -> Rendered {
        let title = subjectTitle(assignmentTitle, courseCode: courseCode, hideCourseNames: hideCourseNames)
        let body = isFinalReminder ? "Due \(dueTimeText), if you haven't submitted yet." : "Due \(dueTimeText)."
        return Rendered(title: title, body: body)
    }

    /// The missing-still-open follow-up ("Still accepted until Fri 11:59 PM.").
    public static func missingFollowup(
        assignmentTitle: String, courseCode: String, stillAcceptedUntilText: String, hideCourseNames: Bool
    ) -> Rendered {
        Rendered(
            title: subjectTitle(assignmentTitle, courseCode: courseCode, hideCourseNames: hideCourseNames),
            body: "Still accepted until \(stillAcceptedUntilText).")
    }

    /// An exam reminder (T-3d/T-1d/morning-of).
    public static func examReminder(
        assignmentTitle: String, courseCode: String, dueTimeText: String, hideCourseNames: Bool
    ) -> Rendered {
        Rendered(
            title: subjectTitle(assignmentTitle, courseCode: courseCode, hideCourseNames: hideCourseNames),
            body: "Due \(dueTimeText).")
    }

    /// A4: never the score, per R10 and the content table.
    public static func gradePosted(courseCode: String, hideCourseNames: Bool) -> Rendered {
        Rendered(title: "New grade posted", body: courseLabel(courseCode, hideCourseNames: hideCourseNames))
    }

    /// A5: never the score or the goal value (R10 content table).
    public static func belowGoal(courseCode: String, hideCourseNames: Bool) -> Rendered {
        Rendered(
            title: "\(courseLabel(courseCode, hideCourseNames: hideCourseNames)) needs attention",
            body: "Open Tally to see your standing.")
    }

    /// The evening digest ("Tomorrow" · "2 due · Lab Report 4 first").
    public static func eveningDigest(dueCount: Int, firstItemTitle: String?, hideCourseNames: Bool) -> Rendered {
        var body = "\(dueCount) due"
        if let firstItemTitle {
            body += " · \(itemLabel(firstItemTitle, hideCourseNames: hideCourseNames)) first"
        }
        return Rendered(title: "Tomorrow", body: body)
    }

    /// The Sunday week-ahead summary ("This week" · "7 due · busiest Thursday").
    /// Counts only, never a course or assignment name, so `hideCourseNames`
    /// changes nothing here.
    public static func weekAhead(dueCount: Int, busiestDayText: String?) -> Rendered {
        var body = "\(dueCount) due"
        if let busiestDayText { body += " · busiest \(busiestDayText)" }
        return Rendered(title: "This week", body: body)
    }

    /// R17 freshness sentinel.
    public static func sentinel(lastSuccessText: String) -> Rendered {
        Rendered(title: "Tally hasn't refreshed since \(lastSuccessText)", body: "Open Tally to update your reminders.")
    }
}

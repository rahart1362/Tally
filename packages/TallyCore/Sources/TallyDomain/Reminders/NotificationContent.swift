import Foundation

/// A notification's words once the app has phrased a `NotificationMessage` (plan 08 L10N-02:
/// `TallyStrings.NotificationText.render`). The platform schedules these, and the reminders pass
/// compares them ("same identifier, different words"). TallyCore itself builds no words.
public enum NotificationContent {
    public struct Rendered: Sendable, Equatable {
        public let title: String
        public let body: String
        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }
}

/// WP-D02, plan 08 §3.2 (L10N-02): what a notification says, as values. TallyCore builds and
/// tests on Linux and emits no user-facing text; the app's renderer
/// (`TallyStrings.NotificationText`) phrases a message in the student's language and formats its
/// dates in the student's locale and time zone.
///
/// **R10, structurally.** No case carries a score, a percentage, a letter grade or a goal: the
/// payloads are Canvas names, dates, counts and flags only, so a renderer has no grade value to
/// leak (`NotificationMessageTests` walks every case's payload types).
///
/// **"Hide course names" (R10), structurally.** With it on, a message carries no course name or
/// code and no assignment title at all (`.hidden`), not a name the renderer is asked to hide. The
/// toggle hides both course codes and assignment titles, per the UX review's content table,
/// despite its name.
public enum NotificationMessage: Sendable, Equatable {
    /// Who an assignment reminder is about.
    public enum Subject: Sendable, Equatable {
        case assignment(title: String, courseCode: String)
        /// "Hide course names" is on.
        case hidden

        public init(assignmentTitle: String, courseCode: String, hideCourseNames: Bool) {
            self = hideCourseNames ? .hidden : .assignment(title: assignmentTitle, courseCode: courseCode)
        }
    }

    /// The course a course-level notification is about.
    public enum CourseName: Sendable, Equatable {
        case code(String)
        /// "Hide course names" is on.
        case hidden

        public init(courseCode: String, hideCourseNames: Bool) {
            self = hideCourseNames ? .hidden : .code(courseCode)
        }
    }

    /// One item a digest names.
    public enum ItemName: Sendable, Equatable {
        case title(String)
        /// "Hide course names" is on.
        case hidden

        public init(title: String, hideCourseNames: Bool) {
            self = hideCourseNames ? .hidden : .title(title)
        }
    }

    /// The T-24h/T-1h due reminder. The final (soonest) reminder uses the "conditional follow-up"
    /// phrasing, since Tally cannot know at schedule time whether the student has since submitted
    /// (§3.6).
    case due(Subject, dueAt: Date, isFinalReminder: Bool)
    /// The missing-still-open follow-up, with Canvas's closing (lock) date. `nil` when Canvas
    /// lists none: the words then say exactly that, never "still accepted until …".
    case missingFollowup(Subject, stillAcceptedUntil: Date?)
    /// An exam reminder (T-3d/T-1d/morning-of).
    case examReminder(Subject, dueAt: Date)
    /// A4: a grade was posted in this course. Never the grade (R10 content table).
    case gradePosted(CourseName)
    /// A5: the course needs attention. Never the score or the goal (R10 content table).
    case belowGoal(CourseName)
    /// The evening digest: how many items are due, and the first of them.
    case eveningDigest(dueCount: Int, firstItem: ItemName?)
    /// The Sunday week-ahead summary: a count and the busiest day (its start, in the student's
    /// time zone), never a course or assignment name, so "Hide course names" changes nothing here.
    case weekAhead(dueCount: Int, busiestDay: Date?)
    /// R17 freshness sentinel: when Tally last refreshed.
    case sentinel(lastSuccess: Date)
}

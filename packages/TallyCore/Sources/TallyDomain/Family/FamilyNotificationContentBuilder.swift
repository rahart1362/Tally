import Foundation

/// FAM-08's content builder (family-linking.md §6.5): turns plain Canvas facts — a student's
/// name, an assignment title, a course code, dates and counts — into the words-to-be
/// (`FamilyNotificationMessage`), applying "Hide student names" structurally.
///
/// Kept separate from `FamilyNotificationPlanner` (its sibling "planner", same work package) on
/// purpose: the planner alone decides *when* a notification fires and under what id/thread,
/// reading only what it needs for timing (candidates, course codes); this builder alone decides
/// *what it says*, from whatever data the caller currently has on hand (a live snapshot at
/// delivery time, or — as `FamilyNotificationFixturePrivacyTests` does — every fixture/persona
/// in `fixtures/canvas/`, to prove the R10a privacy invariant holds everywhere). Neither
/// function depends on the other; an app-layer pipeline (the student-side precedent is
/// `TallyFeatures/Reminders/ReminderPipeline.swift`) calls both.
public enum FamilyNotificationContentBuilder {
    public static func weekAhead(studentName: String, hideStudentNames: Bool, dueCount: Int, busiestDay: Date?) -> FamilyNotificationMessage {
        .weekAhead(student: .init(name: studentName, hideStudentNames: hideStudentNames), dueCount: dueCount, busiestDay: busiestDay)
    }

    public static func missingStillOpen(studentName: String, hideStudentNames: Bool, assignmentTitle: String,
                                        stillAcceptedUntil: Date?) -> FamilyNotificationMessage {
        .missingStillOpen(student: .init(name: studentName, hideStudentNames: hideStudentNames),
                          assignmentTitle: assignmentTitle, stillAcceptedUntil: stillAcceptedUntil)
    }

    public static func dueReminder(studentName: String, hideStudentNames: Bool, assignmentTitle: String,
                                   dueAt: Date, isFinalReminder: Bool) -> FamilyNotificationMessage {
        .dueReminder(student: .init(name: studentName, hideStudentNames: hideStudentNames),
                    assignmentTitle: assignmentTitle, dueAt: dueAt, isFinalReminder: isFinalReminder)
    }

    /// Never takes a grade or score — only the course code it was posted in (§6.5 content table).
    public static func gradePosted(studentName: String, hideStudentNames: Bool, courseCode: String) -> FamilyNotificationMessage {
        .gradePosted(student: .init(name: studentName, hideStudentNames: hideStudentNames), courseCode: courseCode)
    }

    /// Never takes a score or a goal value — *whether* a course is below goal is the caller's
    /// decision (e.g. comparing `Course.scores` against a parent-set threshold); this builder
    /// only ever sees the course code the decision was already made about (§6.5 content table).
    public static func belowGoal(studentName: String, hideStudentNames: Bool, courseCode: String) -> FamilyNotificationMessage {
        .belowGoal(student: .init(name: studentName, hideStudentNames: hideStudentNames), courseCode: courseCode)
    }
}

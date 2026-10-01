import Foundation

/// A parent notification's words, before `TallyStrings.FamilyNotificationText` phrases them
/// (plan 08 L10N-02 pattern; family-linking.md §6.5, FAM-08). TallyCore builds no words itself;
/// see the student-side `NotificationContent.swift`'s sibling doc comment for the same split.
///
/// **R10a, structurally — this is the point of FAM-08.** Every case's payload is a student-name
/// reference, a Canvas assignment title or course code, a date, a count or a flag — **never a
/// `Double`, and never a dedicated grade-shaped `String`.** A course's actual score, percentage
/// or letter grade can gate *whether* `.gradePosted`/`.belowGoal` fires — the planner's caller
/// decides that upstream (`FamilySubjectPlanInput.newlyGradedCourseCodes` /
/// `.belowGoalCourseCodes` are themselves just course codes, never scores) — but no FAM-08 type
/// anywhere, from planner input to this message to the renderer, ever holds a score or a goal
/// value. A renderer literally has nothing to leak.
///
/// `FamilyNotificationPrivacyTests` walks every case's payload types with `Mirror` to prove this
/// structurally (so a future case can't reintroduce a `Double` unnoticed), and a second,
/// fixture-driven property test renders every message producible from every fixture/persona in
/// `fixtures/canvas/` and confirms none of that fixture's own formatted score/percentage/letter-
/// grade text ever appears in the rendered title or body (FAM-08's acceptance criterion, in
/// `FamilyNotificationFixturePrivacyTests`).
///
/// **"Hide student names"** (family-linking.md §6.5, default off): replaces every name with
/// "Your student" **structurally** (`StudentNameRef.hidden`) — not a name the renderer is asked
/// to hide, exactly like the student renderer's own "Hide course names" (`NotificationMessage.
/// Subject`).
public enum FamilyNotificationMessage: Sendable, Equatable {
    /// Which student a parent notification is about, or hidden.
    public enum StudentNameRef: Sendable, Equatable {
        case named(String)
        /// "Hide student names" is on.
        case hidden

        public init(name: String, hideStudentNames: Bool) {
            self = hideStudentNames ? .hidden : .named(name)
        }
    }

    /// Sunday week-ahead summary for one student (§6.5: "Maya's week" / "5 due · busiest Thu").
    case weekAhead(student: StudentNameRef, dueCount: Int, busiestDay: Date?)
    /// Missing, still open (§6.5: "Maya · Problem Set 6" / "Still accepted until Fri 11:59 PM.").
    /// `stillAcceptedUntil == nil` when Canvas lists no closing date (mirrors the student
    /// `NotificationMessage.missingFollowup` case) — the words then say exactly that, never
    /// "still accepted until …", and never the points lost.
    case missingStillOpen(student: StudentNameRef, assignmentTitle: String, stillAcceptedUntil: Date?)
    /// The 24h/1h due reminder (§6.5: off by default — "the student's own reminders do this").
    /// `isFinalReminder` picks the "if your student hasn't submitted yet" phrasing, since Tally
    /// cannot know at schedule time whether the work has since been turned in.
    case dueReminder(student: StudentNameRef, assignmentTitle: String, dueAt: Date, isFinalReminder: Bool)
    /// A grade was posted in this course. Never the grade (§6.5 content table).
    case gradePosted(student: StudentNameRef, courseCode: String)
    /// The course needs attention. Never the score or the goal (§6.5 content table).
    case belowGoal(student: StudentNameRef, courseCode: String)
}

import Foundation

/// Family-linking parent notifications (plan 08 L10N-02 pattern; family-linking.md §6.5,
/// FAM-08). A file of its own — not `L10n.swift` — so that shared file stays untouched while
/// three streams work on it in parallel (that file's own "How to add a string" note recommends
/// exactly this for a new area).
extension L10n {
    public enum Family {
        /// The Sunday week-ahead summary's title: "Maya's week" (or "Your student's week" with
        /// Hide Student Names on).
        public static func weekAheadTitle(student: String) -> LocalizedStringResource {
            LocalizedStringResource("family.notification.weekAhead.title", defaultValue: "\(student)'s week", bundle: #bundle,
                                    comment: "Parent notification title: the Sunday week-ahead summary for one linked student. The argument is the student's first name, or 'Your student' when the parent turned on Hide Student Names.")
        }

        public static func weekAheadBody(_ count: Int) -> LocalizedStringResource {
            LocalizedStringResource("family.notification.weekAhead.count", defaultValue: "\(count) due", bundle: #bundle,
                                    comment: "Parent notification body: how many items are due in the student's next 7 days. Never the student's grade.")
        }

        public static func weekAheadBodyWithBusiest(_ count: Int, _ day: String) -> LocalizedStringResource {
            LocalizedStringResource("family.notification.weekAhead.countWithBusiest", defaultValue: "\(count) due \u{00b7} busiest \(day)", bundle: #bundle,
                                    comment: "Parent notification body. 1: how many items are due in the student's next 7 days. 2: the weekday with the most, such as 'Thursday'.")
        }

        /// The student + assignment title pairing shared by "missing, still open" and the 24h/
        /// 1h due reminder: "Maya · Problem Set 6" (§6.5). No course code in the title — unlike
        /// the student's own reminders, the parent's copy never names the course here.
        public static func subjectTitle(student: String, assignmentTitle: String) -> LocalizedStringResource {
            LocalizedStringResource("family.notification.subject.title", defaultValue: "\(student) \u{00b7} \(assignmentTitle)", bundle: #bundle,
                                    comment: "Parent notification title naming a student and one assignment. 1: the student's first name, or 'Your student'. 2: the assignment's title from Canvas.")
        }

        public static func stillAcceptedUntil(_ when: String) -> LocalizedStringResource {
            LocalizedStringResource("family.notification.missing.stillAcceptedUntil", defaultValue: "Still accepted until \(when).", bundle: #bundle,
                                    comment: "Parent notification body: Canvas still accepts the student's work until this day and time, such as 'Fri at 11:59 PM'. Never the points lost.")
        }

        public static func noClosingDate() -> LocalizedStringResource {
            LocalizedStringResource("family.notification.missing.noClosingDate", defaultValue: "Past due. Canvas lists no closing date.", bundle: #bundle,
                                    comment: "Parent notification body when Canvas gives no date after which the student's work is no longer accepted.")
        }

        public static func dueBody(_ when: String) -> LocalizedStringResource {
            LocalizedStringResource("family.notification.due.body", defaultValue: "Due \(when).", bundle: #bundle,
                                    comment: "Parent due-date reminder body. The argument is a day and time, such as 'today at 6:00 PM'.")
        }

        public static func dueFinalBody(_ when: String) -> LocalizedStringResource {
            LocalizedStringResource("family.notification.due.finalBody", defaultValue: "Due \(when), if your student hasn't submitted yet.", bundle: #bundle,
                                    comment: "Parent's last due-date reminder body: Tally cannot know whether the work was submitted since. The argument is a day and time, such as 'today at 6:00 PM'.")
        }

        public static func gradePostedTitle(student: String) -> LocalizedStringResource {
            LocalizedStringResource("family.notification.gradePosted.title", defaultValue: "\(student) \u{00b7} New grade posted", bundle: #bundle,
                                    comment: "Parent notification title: a new grade was posted for the named student. The grade itself is never shown. The argument is the student's first name, or 'Your student'.")
        }

        public static func belowGoalTitle(student: String, courseCode: String) -> LocalizedStringResource {
            LocalizedStringResource("family.notification.belowGoal.title", defaultValue: "\(student) \u{00b7} \(courseCode) needs attention", bundle: #bundle,
                                    comment: "Parent notification title: a course needs attention for the named student. 1: the student's first name, or 'Your student'. 2: the course code from Canvas. Never the score or goal.")
        }

        public static func belowGoalBody() -> LocalizedStringResource {
            LocalizedStringResource("family.notification.belowGoal.body", defaultValue: "Open Tally to see details.", bundle: #bundle,
                                    comment: "Parent notification body for the 'needs attention' notification. Never the score or goal value.")
        }

        /// "Hide Student Names" (default off, family-linking.md §6.5): stands for a linked
        /// student's name everywhere a parent notification would otherwise show it.
        public static func hiddenStudent() -> LocalizedStringResource {
            LocalizedStringResource("family.notification.student.hidden", defaultValue: "Your student", bundle: #bundle,
                                    comment: "Stands for a linked student's name in a parent notification when the parent turned on Hide Student Names.")
        }
    }
}

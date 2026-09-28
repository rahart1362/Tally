import Foundation
import TallyDomain

/// ASC-14: shifts every Canvas-content date in a fixture-derived `CanvasSnapshot` forward so
/// due dates "look current" in demo mode, per `fixtures/canvas/README.md`'s "Rebasing for demo
/// mode" rule:
///
/// > 1. `days = local_date(now, tz) - local_date(ANCHOR, tz)`, where `tz` is the persona's time
/// >    zone and `ANCHOR` is the fixture's capture instant. Only whole days are shifted, so
/// >    "today" in demo mode shows the anchor day's content and every class meeting keeps its
/// >    local wall-clock time. 2. Every timestamp is converted to local wall-clock time in `tz`,
/// >    its date moved by `days`, and converted back (so 11:59 pm stays 11:59 pm across a DST
/// >    change). 3. A plain date moves by `days`. 4. Nothing else changes: ids, URLs, durations
/// >    and scores stay as they are.
///
/// The README's reference implementation (`tools/canvas-synth/canvas_synth/rebase.py`) rewrites
/// the raw Canvas JSON before it is served. This type applies the identical rule one layer
/// later, to the already-decoded `CanvasSnapshot` — every `Date` field that originated in a
/// Canvas response, after `LiveCanvasGateway`'s DTO mappers have run. That is equivalent for
/// every field this domain model actually carries (rule 4's "ids, URLs... stay as they are" is
/// automatic here, since ids/URLs are simply never touched), and it reuses the exact
/// `Calendar`-based wall-clock/DST handling `CanvasDateWindow` already relies on elsewhere,
/// rather than re-deriving a JSON-string ISO-8601 rewriter. Disclosed design choice (PMO report).
///
/// `CanvasSnapshot.fetchedAt` and every `SectionStatus.fetchedAt` are deliberately **not**
/// shifted: `LiveCanvasGateway` stamps those from the real `now` passed into `fetchSnapshot`,
/// not from fixture data, so they are already correct (rule 4 again: only Canvas-content dates
/// move).
/// `nonisolated`: `TallyFeatures` defaults to `MainActor` isolation (Package.swift), but this is
/// a pure function with no UI/main-thread dependency — marking it explicitly lets it (and its
/// tests) be called synchronously from any context, exactly like `TallyDomain`'s pure types.
public nonisolated enum SnapshotDateRebaser {
    /// `days = local_date(now, tz) - local_date(anchor, tz)`, truncated to whole days.
    public static func dayOffset(from anchor: Date, to now: Date, in timeZone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let anchorDay = calendar.startOfDay(for: anchor)
        let nowDay = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: anchorDay, to: nowDay).day ?? 0
    }

    /// Rebases every Canvas-content date in `snapshot` by the day offset between `anchor` and
    /// `now`, preserving each date's local wall-clock time in `timeZone` across the shift
    /// (`Calendar.date(byAdding:to:)`, configured with `timeZone`, does this by construction —
    /// the same mechanism `CanvasDateWindow` uses for request-window arithmetic).
    public static func rebase(_ snapshot: CanvasSnapshot, anchor: Date, now: Date, timeZone: TimeZone) -> CanvasSnapshot {
        let days = dayOffset(from: anchor, to: now, in: timeZone)
        guard days != 0 else { return snapshot }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        func shift(_ date: Date) -> Date { calendar.date(byAdding: .day, value: days, to: date) ?? date }
        func shift(_ date: Date?) -> Date? { date.map(shift) }

        func shiftSubmission(_ submission: Submission?) -> Submission? {
            guard let submission else { return nil }
            return Submission(
                score: submission.score, grade: submission.grade,
                submittedAt: shift(submission.submittedAt), gradedAt: shift(submission.gradedAt),
                postedAt: shift(submission.postedAt), excused: submission.excused, missing: submission.missing,
                late: submission.late, workflowState: submission.workflowState, id: submission.id,
                gradingPeriodID: submission.gradingPeriodID)
        }

        func shiftAssignment(_ assignment: Assignment) -> Assignment {
            Assignment(
                id: assignment.id, courseID: assignment.courseID, groupID: assignment.groupID, name: assignment.name,
                dueAt: shift(assignment.dueAt), lockAt: shift(assignment.lockAt), pointsPossible: assignment.pointsPossible,
                gradingType: assignment.gradingType, omitFromFinalGrade: assignment.omitFromFinalGrade,
                htmlURL: assignment.htmlURL, submission: shiftSubmission(assignment.submission),
                published: assignment.published, submissionTypes: assignment.submissionTypes)
        }

        func shiftGroup(_ group: AssignmentGroup) -> AssignmentGroup {
            AssignmentGroup(id: group.id, name: group.name, position: group.position, weight: group.weight,
                            rules: group.rules, assignments: group.assignments.map(shiftAssignment))
        }

        func shiftCourse(_ course: Course) -> Course {
            let term = course.term.map { Term(id: $0.id, name: $0.name, startAt: shift($0.startAt), endAt: shift($0.endAt)) }
            return Course(
                id: course.id, name: course.name, courseCode: course.courseCode, term: term, teachers: course.teachers,
                timeZone: course.timeZone, appliesGroupWeights: course.appliesGroupWeights,
                hasGradingPeriods: course.hasGradingPeriods, currentGradingPeriodID: course.currentGradingPeriodID,
                gradeVisibility: course.gradeVisibility, scores: course.scores, currentPeriodScores: course.currentPeriodScores,
                htmlURL: course.htmlURL, hasWeightedGradingPeriods: course.hasWeightedGradingPeriods,
                studentEnrollmentCompleted: course.studentEnrollmentCompleted)
        }

        func shiftGradingPeriod(_ period: GradingPeriod) -> GradingPeriod {
            GradingPeriod(id: period.id, title: period.title, startDate: shift(period.startDate),
                         endDate: shift(period.endDate), closeDate: shift(period.closeDate),
                         weight: period.weight, isClosed: period.isClosed)
        }

        func shiftPlannerItem(_ item: PlannerItem) -> PlannerItem {
            PlannerItem(id: item.id, courseID: item.courseID, title: item.title, plannableType: item.plannableType,
                       dueAt: shift(item.dueAt), pointsPossible: item.pointsPossible, submitted: item.submitted,
                       graded: item.graded, missing: item.missing, late: item.late, excused: item.excused,
                       markedComplete: item.markedComplete, htmlURL: item.htmlURL)
        }

        func shiftEvent(_ event: CalendarEvent) -> CalendarEvent {
            CalendarEvent(id: event.id, courseID: event.courseID, title: event.title, startAt: shift(event.startAt),
                         endAt: shift(event.endAt), allDay: event.allDay, locationName: event.locationName,
                         htmlURL: event.htmlURL)
        }

        func shiftAnnouncement(_ announcement: Announcement) -> Announcement {
            Announcement(id: announcement.id, courseID: announcement.courseID, title: announcement.title,
                        postedAt: shift(announcement.postedAt), isRead: announcement.isRead, htmlURL: announcement.htmlURL)
        }

        return CanvasSnapshot(
            generation: snapshot.generation, accountKey: snapshot.accountKey, host: snapshot.host,
            fetchedAt: snapshot.fetchedAt, // real fetch time — never a fixture date (see doc comment)
            profile: snapshot.profile, courses: snapshot.courses.map(shiftCourse),
            groups: snapshot.groups.mapValues { $0.map(shiftGroup) },
            gradingPeriods: snapshot.gradingPeriods.mapValues { $0.map(shiftGradingPeriod) },
            planner: snapshot.planner.map(shiftPlannerItem), events: snapshot.events.map(shiftEvent),
            announcements: snapshot.announcements.map(shiftAnnouncement), courseColors: snapshot.courseColors,
            sections: snapshot.sections) // fetch metadata, not Canvas content — never shifted
    }
}

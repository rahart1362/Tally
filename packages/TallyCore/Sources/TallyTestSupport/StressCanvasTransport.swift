import Foundation
import TallyCanvasAPI
import TallyDomain

/// PERF-01: renders a `StressSnapshotFixture` scale back into raw Canvas-shaped JSON — the
/// mirror image of `CourseMapper`/`AssignmentGroupMapper`/`PlannerItemMapper`/`ProfileMapper` —
/// so `LiveCanvasGateway.fetchSnapshot` and the mappers themselves can be benchmarked at stress
/// scale over their real code path. Every byte is generated in memory (`JSONSerialization`,
/// never written to disk), matching the charter's "not a fixture file" rule for this scale.
///
/// Only the four **required** sections (profile, courses, assignment groups, planner) are
/// rendered: architecture.md §3.2 makes the optional sections (grading periods, events,
/// announcements, colors) independently failable and carry-forward safe, so leaving them
/// unregistered on the transport below (they 404 against `errors/404-not-found`, the same
/// fixture every other persona's replay already falls back to) is a faithful partial-failure
/// run, not a shortcut — `LiveCanvasGateway.fetchSnapshot` still succeeds, just with those
/// sections empty. The grading-period-bearing pure-function benchmarks use
/// `StressSnapshotFixture.make()`'s in-memory `CanvasSnapshot` directly instead, which does
/// carry real grading periods.
public enum StressCanvasJSON {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static func json(_ any: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: any)) ?? Data("[]".utf8)
    }

    /// `yyyy-MM-ddTHH:mm:ssZ`, matching `CanvasDate.parse`'s pattern exactly — no
    /// `ISO8601DateFormatter` (not `Sendable`; this is a global-scope pure function instead of
    /// stored formatter state, so there is nothing to synchronize).
    private static func iso8601(_ date: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02dZ",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    private static func string(_ date: Date?) -> Any { date.map(iso8601) ?? NSNull() }

    public static func profile(_ profile: UserProfile) -> Data {
        json(["id": profile.id.rawValue, "name": profile.name, "short_name": profile.shortName as Any,
              "time_zone": profile.timeZone as Any])
    }

    /// One page containing every course (the stress scale's course count comfortably fits
    /// Canvas's real `per_page` ceiling, so no `Link` header/second page is needed).
    public static func courses(_ courses: [Course]) -> Data {
        json(courses.map { course -> [String: Any] in
            [
                "id": course.id.rawValue,
                "name": course.name,
                "course_code": course.courseCode,
                "time_zone": course.timeZone as Any,
                "apply_assignment_group_weights": course.appliesGroupWeights,
                "has_grading_periods": course.hasGradingPeriods,
                "has_weighted_grading_periods": course.hasWeightedGradingPeriods,
                "hide_final_grades": course.gradeVisibility == .hiddenTotals,
                "restrict_quantitative_data": course.gradeVisibility == .lettersOnly,
                "access_restricted_by_date": false,
                "term": course.term.map { ["id": $0.id.rawValue, "name": $0.name, "start_at": string($0.startAt),
                                           "end_at": string($0.endAt)] } as Any,
                "teachers": course.teachers.map { ["id": $0.id.rawValue, "display_name": $0.displayName] },
                "enrollments": [[
                    "type": "student", "enrollment_state": "active",
                    "computed_current_score": course.scores?.currentScore as Any,
                    "computed_final_score": course.scores?.finalScore as Any,
                ]],
            ]
        })
    }

    /// One page per course containing every one of its assignments (same rationale as `courses`).
    public static func assignmentGroups(_ groups: [AssignmentGroup], courseID: CanvasID<Course>) -> Data {
        json(groups.map { group -> [String: Any] in
            [
                "id": group.id.rawValue, "name": group.name, "position": group.position,
                "group_weight": group.weight as Any,
                "rules": ["drop_lowest": group.rules.dropLowest, "drop_highest": group.rules.dropHighest,
                          "never_drop": group.rules.neverDrop.map(\.rawValue)],
                "assignments": group.assignments.map { assignment -> [String: Any] in
                    [
                        "id": assignment.id.rawValue, "name": assignment.name, "course_id": courseID.rawValue,
                        "due_at": string(assignment.dueAt), "lock_at": string(assignment.lockAt),
                        "points_possible": assignment.pointsPossible as Any,
                        "grading_type": "points", "omit_from_final_grade": assignment.omitFromFinalGrade,
                        "published": assignment.published, "submission_types": assignment.submissionTypes,
                        "submission": assignment.submission.map { s -> [String: Any] in
                            [
                                "id": s.id?.rawValue as Any, "score": s.score as Any, "grade": s.grade as Any,
                                "submitted_at": string(s.submittedAt), "graded_at": string(s.gradedAt),
                                "posted_at": string(s.postedAt), "excused": s.excused, "missing": s.missing,
                                "late": s.late, "workflow_state": s.workflowState,
                                "grading_period_id": s.gradingPeriodID?.rawValue as Any,
                            ]
                        } as Any,
                    ]
                },
            ]
        })
    }

    /// One page containing every planner item.
    public static func plannerItems(_ items: [PlannerItem]) -> Data {
        json(items.map { item -> [String: Any] in
            [
                "course_id": item.courseID?.rawValue as Any,
                "plannable_id": String(item.id.split(separator: ":").last ?? ""),
                "plannable_type": item.plannableType,
                "plannable_date": string(item.dueAt),
                "plannable": ["title": item.title, "points_possible": item.pointsPossible as Any],
                "submissions": ["submitted": item.submitted, "excused": item.excused, "graded": item.graded,
                                "missing": item.missing, "late": item.late],
                "planner_override": ["marked_complete": item.markedComplete],
            ]
        })
    }
}

/// Builds a `ReplayTransport` whose required-section routes are served entirely from
/// in-memory JSON rendered by `StressCanvasJSON` — no on-disk fixture — via `inject`, so
/// `LiveCanvasGateway.fetchSnapshot` runs its real pagination/mapping/partial-failure code path
/// at stress scale. `courseID`s are read back off `snapshot.courses`/`snapshot.groups`, so the
/// caller only needs to pass the same `CanvasSnapshot` `StressSnapshotFixture` built.
public enum StressCanvasTransport {
    /// `inject` is actor-isolated, so building the transport is async: `await` this once per
    /// benchmark iteration's setup, outside the timed region.
    public static func prepare(from snapshot: CanvasSnapshot) async -> ReplayTransport {
        let transport = ReplayTransport(routes: [])
        await register(snapshot, on: transport)
        return transport
    }

    /// Every injection is registered `times: repeatCount`, not once: a benchmark calls
    /// `fetchSnapshot` repeatedly against the *same* transport instance (one warmup pass plus
    /// several timed iterations), and `ReplayTransport.inject`'s canned responses are consumed
    /// on match — a `times: 1` route would 404 (a required section, so `fetchSnapshot` itself
    /// would throw) from the second call onward.
    private static func register(_ snapshot: CanvasSnapshot, on transport: ReplayTransport, repeatCount: Int = 64) async {
        await transport.inject(response: HTTPResponse(status: 200, body: StressCanvasJSON.profile(snapshot.profile)),
                               times: repeatCount) { $0.url.path == "/api/v1/users/self/profile" }
        await transport.inject(response: HTTPResponse(status: 200, body: StressCanvasJSON.courses(snapshot.courses)),
                               times: repeatCount) { $0.url.path == "/api/v1/courses" }
        await transport.inject(response: HTTPResponse(status: 200, body: StressCanvasJSON.plannerItems(snapshot.planner)),
                               times: repeatCount) { $0.url.path == "/api/v1/planner/items" }
        for course in snapshot.courses {
            let path = "/api/v1/courses/\(course.id.rawValue)/assignment_groups"
            let body = StressCanvasJSON.assignmentGroups(snapshot.groups[course.id] ?? [], courseID: course.id)
            await transport.inject(response: HTTPResponse(status: 200, body: body), times: repeatCount) { $0.url.path == path }
        }
    }
}

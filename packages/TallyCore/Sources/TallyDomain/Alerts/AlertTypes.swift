import Foundation

/// insights-at-a-glance §2.2: one severity model shared by the in-app
/// "Needs attention" list, pushes and the digest.
public enum AlertSeverity: Int, Sendable, Equatable, Hashable, Comparable, Codable, CaseIterable {
    case info = 100
    case medium = 200
    case high = 300
    case critical = 400

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// §2.1's A12 sync/sign-in conditions.
public enum SyncCondition: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case authExpired
    case staleOver24h
    case notificationsOffRulesOn
    case backgroundRefreshOff
    case schoolNotEnabled
}

/// The seven alert categories this work package covers (missing, due soon,
/// grade posted, below goal/threshold, overload cluster, schedule conflict,
/// sync/sign-in state), each carrying only opaque Canvas IDs — never a
/// title, score or body — so it is safe to persist in backed-up
/// `user-state` (ENC D-E4) and never logs student content (implementation
/// brief hard rule 3). Rendering (titles, grade values) is the app layer's
/// job, reading the same snapshot this was computed from.
///
/// A6 "significant drop" is folded into `.belowGoal`'s family here as a
/// distinct case (`.significantDrop`) rather than a separate top-level type,
/// since the UX review documents it as "superseded by A5 for the same
/// course" — i.e. a variant severity signal on the same subject, not an
/// unrelated alert family.
public enum AlertKind: Sendable, Equatable, Hashable {
    /// A1: missing and still accepted (`lock_at` nil or in the future).
    case missingOpen(assignmentID: CanvasID<Assignment>)
    /// A2: missing and closed (`lock_at` has passed); grouped per course.
    case missingClosed(courseID: CanvasID<Course>)
    /// A3: needs submission, not submitted, due within 72 h.
    case dueSoon(assignmentID: CanvasID<Assignment>)
    /// A4: a new posted grade since the last seen snapshot.
    case gradePosted(submissionID: CanvasID<Submission>, postedAt: Date)
    /// A5: course score below the student's goal (or threshold).
    case belowGoal(courseID: CanvasID<Course>)
    /// A6: a significant score drop, superseded by `.belowGoal` for the same course.
    case significantDrop(courseID: CanvasID<Course>, weekOf: Date)
    /// A7: a rolling-window cluster of due items or course weight.
    case overloadCluster(windowStart: Date)
    /// A8: two schedule items (classes, exams or due instants) in conflict.
    case scheduleConflict(idA: String, idB: String)
    /// A12: sync/sign-in state.
    case sync(SyncCondition)

    /// §2.3 "Identity: every alert has a stable key built from Canvas IDs."
    public var dedupeKey: String {
        switch self {
        case .missingOpen(let id): "missing:\(id.rawValue)"
        case .missingClosed(let course): "missingClosed:\(course.rawValue)"
        case .dueSoon(let id): "due:\(id.rawValue)"
        case .gradePosted(let submission, let postedAt):
            "graded:\(submission.rawValue):\(Int(postedAt.timeIntervalSince1970))"
        case .belowGoal(let course): "belowGoal:\(course.rawValue)"
        case .significantDrop(let course, let weekOf):
            "drop:\(course.rawValue):\(Int(weekOf.timeIntervalSince1970 / 604_800))"
        case .overloadCluster(let start): "overload:\(Int(start.timeIntervalSince1970))"
        case .scheduleConflict(let a, let b): "conflict:\(min(a, b)):\(max(a, b))"
        case .sync(let condition): "sys:\(condition.rawValue)"
        }
    }
}

/// One raised alert. `priority` is the §5 priority score (0...99) for the
/// same subject when one applies (due-soon/missing items), used only to
/// order within a severity band (§2.2 `rank`); it is 0 otherwise.
public struct Alert: Sendable, Equatable {
    public let kind: AlertKind
    public let severity: AlertSeverity
    public let courseID: CanvasID<Course>?
    public let priority: Int

    public init(kind: AlertKind, severity: AlertSeverity, courseID: CanvasID<Course>? = nil, priority: Int = 0) {
        self.kind = kind
        self.severity = severity
        self.courseID = courseID
        self.priority = max(0, min(99, priority))
    }

    public var dedupeKey: String { kind.dedupeKey }

    /// §2.2: `rank = severityBase + itemPriority`. Higher ranks sort first.
    public var rank: Int { severity.rawValue + priority }
}

/// §2.3 per-key alert state, backed up in `user-state` (opaque IDs only).
public struct AlertState: Sendable, Equatable, Codable {
    public var seen: Bool
    public var dismissedAt: Date?
    public var dismissedSeverity: AlertSeverity?
    public var snoozedUntil: Date?

    public init(seen: Bool = false, dismissedAt: Date? = nil, dismissedSeverity: AlertSeverity? = nil, snoozedUntil: Date? = nil) {
        self.seen = seen
        self.dismissedAt = dismissedAt
        self.dismissedSeverity = dismissedSeverity
        self.snoozedUntil = snoozedUntil
    }
}

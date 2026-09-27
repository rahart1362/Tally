import Foundation

/// How big a course-grade move must be to appear in "What changed" (owner decision, 2026-09-27):
/// 0.5 points by default, user-configurable as "All" or a point value, globally or per course.
public enum ScoreChangeThreshold: Codable, Sendable, Equatable, Hashable {
    /// Report every course-grade change, however small.
    case all
    /// Report a change only when it moves at least this many percentage points (up or down).
    case points(Double)

    public static let `default`: ScoreChangeThreshold = .points(TallyConfig.courseScoreChangeThreshold)

    /// Whether a move of `delta` points (either direction) clears this threshold.
    public func isCleared(by delta: Double) -> Bool {
        let magnitude = abs(delta)
        switch self {
        case .all: return magnitude > 0
        case .points(let minimum): return magnitude > 0 && magnitude >= max(0, minimum)
        }
    }
}

/// The user's digest settings: one global threshold plus optional per-course overrides.
public struct DigestThresholds: Codable, Sendable, Equatable {
    public var global: ScoreChangeThreshold
    public var perCourse: [CanvasID<Course>: ScoreChangeThreshold]

    public static let `default` = DigestThresholds()

    public init(global: ScoreChangeThreshold = .default, perCourse: [CanvasID<Course>: ScoreChangeThreshold] = [:]) {
        self.global = global
        self.perCourse = perCourse
    }

    /// The threshold that applies to one course: its override if set, otherwise the global one.
    public func threshold(for course: CanvasID<Course>) -> ScoreChangeThreshold {
        perCourse[course] ?? global
    }
}

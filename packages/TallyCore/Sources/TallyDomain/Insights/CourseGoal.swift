import Foundation

/// A student-set target percentage for one course (insights-at-a-glance §1.2
/// "Goal tracker", §5: below-goal alerts and the priority score's `C`
/// modifier). Goals are user-authored `user-state`, not Canvas data — there is
/// no Canvas endpoint for them — so this lives alongside the insights lane
/// rather than on `Course` (which is mapped straight from Canvas responses).
public struct CourseGoal: Sendable, Equatable, Codable {
    public let courseID: CanvasID<Course>
    /// 0...100.
    public let targetPercent: Double

    public init(courseID: CanvasID<Course>, targetPercent: Double) {
        self.courseID = courseID
        self.targetPercent = targetPercent
    }
}

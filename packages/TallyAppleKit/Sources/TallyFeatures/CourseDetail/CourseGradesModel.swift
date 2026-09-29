import Foundation
import Observation
import TallyDomain

/// The Grades segment's category percentages (ux-ui.md §3.7.3 "Grades: a table of category,
/// weight, current %"). Canvas gives only course totals, so each category's current percentage is
/// the domain engine's (`EnrollmentScores.posted.currentGroups`), computed through `GradeWork`: off
/// the main actor and cancellable with the view's task.
@MainActor
@Observable
public final class CourseGradesModel {
    /// Explicit and nonisolated (plan 06 A2; swiftlang/swift#88036).
    nonisolated deinit {}

    /// Each category's current percentage (graded work only); a category with nothing graded yet
    /// has none.
    public private(set) var categoryPercents: [CanvasID<AssignmentGroup>: Double] = [:]
    @ObservationIgnored private var loadedInput: GradeInput?

    public init() {}

    /// Computes the percentages for `input`, unless they are already on screen.
    public func load(_ input: GradeInput?) async {
        guard let input, input != loadedInput else { return }
        guard let scores = try? await GradeWork.scores(for: input) else { return } // cancelled
        var percents: [CanvasID<AssignmentGroup>: Double] = [:]
        for group in scores.posted.currentGroups where percents[group.groupID] == nil {
            if let grade = group.grade { percents[group.groupID] = grade }
        }
        categoryPercents = percents
        loadedInput = input
    }
}

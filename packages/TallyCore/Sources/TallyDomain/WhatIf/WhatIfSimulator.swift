import Foundation

/// WP-A06: a hypothetical-score overlay for the course grade what-if simulator
/// (UX review §3.7.3). Overlays never mutate the snapshot or the `GradeInput`
/// passed in; `apply` returns a new value, and `GradeEngine` (verified,
/// Canvas-parity grade math) recomputes the grade from it. This mirrors why
/// the UX review insists the computation "must be local": Canvas's What-If
/// Grades API is a `PUT` per submission and is documented as too costly for
/// live interaction, so Tally never calls it.
public enum WhatIfSimulator {
    /// One hypothetical score for an assignment, as if it had just been graded.
    public struct Override: Sendable, Equatable {
        public let assignmentID: CanvasID<Assignment>
        public let score: Double
        public init(assignmentID: CanvasID<Assignment>, score: Double) {
            self.assignmentID = assignmentID
            self.score = score
        }
    }

    /// Returns a copy of `input` with every named assignment's submission
    /// replaced by a hypothetical one scoring `score`: posted, graded, and not
    /// excused, because a what-if always answers "if this were graded `score`
    /// right now", never "if this were excused" or "if this were hidden from
    /// me". Assignments not named in `overrides` keep their real state
    /// (including "no submission yet", pending review, unposted, excused).
    ///
    /// An empty `overrides` returns `input` unchanged, so a what-if with no
    /// hypothetical scores reproduces the current grade exactly (identity
    /// property, WP-A06 acceptance criterion).
    public static func apply(_ overrides: [Override], to input: GradeInput) -> GradeInput {
        guard !overrides.isEmpty else { return input }
        var byAssignment: [CanvasID<Assignment>: Double] = [:]
        for override in overrides { byAssignment[override.assignmentID] = override.score }

        var overlaid = input
        overlaid.items = input.items.map { item in
            guard let score = byAssignment[item.id] else { return item }
            var item = item
            item.submission = GradeInput.ScoredSubmission(
                id: item.submission?.id, score: score, excused: false, posted: true, workflowState: "graded")
            return item
        }
        return overlaid
    }

    /// Convenience: the `EnrollmentScores` `GradeEngine` computes for `input`
    /// with `overrides` overlaid. Never mutates `input`.
    public static func scores(applying overrides: [Override], to input: GradeInput) -> EnrollmentScores {
        GradeEngine.scores(for: apply(overrides, to: input))
    }
}

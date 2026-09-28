import Dispatch
import Foundation
import Synchronization
import TallyDomain

/// The app's only way to run grade math (plan 06 A8; crash-safety-2.md decision D2(b)):
/// `GradeEngine`, `GoalSeek` and `WhatIfSimulator` are synchronous and, on extreme inputs, take
/// seconds to minutes (F-5: 91 s for one 50-item group spanning 1e300 and 1e-300 in a debug
/// build; `GoalSeek` calls the engine about 62 times). So every call:
/// - runs off the main actor, on a dedicated queue rather than the cooperative pool, which a long
///   computation would otherwise hold a thread of;
/// - can be cancelled: a cancelled caller gets `CancellationError` at once. The computation
///   itself cannot be interrupted part-way; it finishes on its queue and its result is dropped.
///
/// CI's hygiene job fails if any other file in the app calls these engines directly.
nonisolated enum GradeWork {
    private static let queue = DispatchQueue(label: "dev.tally-app.grade-work", qos: .userInitiated,
                                             attributes: .concurrent)

    /// `GradeEngine.scores(for:)`: current, final and per-period scores.
    @concurrent
    static func scores(for input: GradeInput) async throws -> EnrollmentScores {
        try await run { GradeEngine.scores(for: input) }
    }

    /// What-if: the scores with `overrides` applied.
    @concurrent
    static func scores(applying overrides: [WhatIfSimulator.Override], to input: GradeInput) async throws -> EnrollmentScores {
        try await run { WhatIfSimulator.scores(applying: overrides, to: input) }
    }

    /// Goal seek: the lowest score on `assignmentID` that reaches `targetPercent`.
    @concurrent
    static func goalSeek(
        assignmentID: CanvasID<Assignment>, targetPercent: Double, in input: GradeInput,
        branch: GoalSeek.Branch = .current
    ) async throws -> GoalSeek.Result {
        try await run { GoalSeek.solve(assignmentID: assignmentID, targetPercent: targetPercent, in: input, branch: branch) }
    }

    /// Runs `work` on the grade queue and returns its value, or throws `CancellationError` as soon
    /// as the calling task is cancelled (at once if it already was).
    static func run<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async throws -> Value {
        try Task.checkCancellation()
        let gate = OnceGate<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
                gate.install(continuation)
                queue.async { gate.finish(.success(work())) }
            }
        } onCancel: {
            gate.finish(.failure(CancellationError()))
        }
    }
}

/// Resumes one continuation exactly once, with whichever outcome arrives first: the result, or
/// the caller's cancellation. An outcome that arrives before the continuation is installed is
/// kept and delivered on install.
private nonisolated final class OnceGate<Value: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Value, any Error>?
        var early: Result<Value, any Error>?
        var done = false
    }

    private let state = Mutex(State())

    func install(_ continuation: CheckedContinuation<Value, any Error>) {
        let early = state.withLock { state -> Result<Value, any Error>? in
            if let early = state.early {
                state.early = nil
                state.done = true
                return early
            }
            state.continuation = continuation
            return nil
        }
        if let early { continuation.resume(with: early) }
    }

    func finish(_ outcome: Result<Value, any Error>) {
        let continuation = state.withLock { state -> CheckedContinuation<Value, any Error>? in
            guard !state.done else { return nil }
            guard let continuation = state.continuation else {
                if state.early == nil { state.early = outcome }
                return nil
            }
            state.continuation = nil
            state.done = true
            return continuation
        }
        continuation?.resume(with: outcome)
    }
}

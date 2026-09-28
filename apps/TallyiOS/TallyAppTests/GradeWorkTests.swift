import Foundation
import Synchronization
import Testing
import TallyDomain
@testable import TallyFeatures

/// Plan 06 A8, crash-safety-2.md decision D2(b): grade math runs off the main actor and can be
/// cancelled, because `GradeEngine`/`GoalSeek` take seconds to minutes on extreme inputs (F-5).
@Suite("GradeWork: grade math off the main actor, cancellable")
struct GradeWorkTests {
    /// Set from any thread.
    final class Flag: Sendable {
        private let state = Mutex(false)
        func set() { state.withLock { $0 = true } }
        var value: Bool { state.withLock { $0 } }
    }

    @Test("scores(for:) equals GradeEngine's, and the work runs off the main thread even when awaited from the main actor")
    @MainActor
    func scoresMatchTheEngineOffMain() async throws {
        let snapshot = try await FlagshipSnapshotHarness.fetchSnapshot()
        let course = try #require(snapshot.courses.first)
        let input = GradeInput(course: course, groups: snapshot.groups[course.id] ?? [],
                               gradingPeriods: snapshot.gradingPeriods[course.id] ?? [])
        #expect(try await GradeWork.scores(for: input) == GradeEngine.scores(for: input))
        #expect(try await GradeWork.run { pthread_main_np() != 0 } == false)
    }

    @Test("a cancelled caller stops waiting at once; the computation finishes on its queue and is dropped")
    func cancellationReturnsAtOnce() async throws {
        let finished = Flag()
        let work = Task {
            try await GradeWork.run {
                Thread.sleep(forTimeInterval: 1) // a long synchronous computation
                finished.set()
                return 1
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        let cancelledAt = ContinuousClock.now
        work.cancel()
        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(ContinuousClock.now - cancelledAt < .milliseconds(500), "the cancelled caller kept waiting")
        #expect(!finished.value, "the caller only returned once the computation had finished")
    }

    @Test("an already-cancelled caller throws before any work starts")
    func preCancelledCallerNeverStarts() async {
        let started = Flag()
        let work = Task {
            try? await Task.sleep(for: .seconds(10)) // returns at once: the task is cancelled
            return try await GradeWork.run {
                started.set()
                return 1
            }
        }
        work.cancel()
        await #expect(throws: CancellationError.self) { try await work.value }
        #expect(!started.value)
    }
}

import Foundation
import Synchronization
import Testing
import TallyDomain
@testable import TallyFeatures

/// perf-app-runtime.md §7 step 5: sample entry runs off the main actor. The gateway's bundle I/O
/// happens in `SampleDataCanvasGateway.make()`, and the replay, mapping, rebase and digest run on
/// the `SampleSession` actor; `TaskBox` owns the model's subscription.
@Suite("Sample session: off-main entry, updates, end()")
struct SampleSessionTests {
    /// Records what a `@Sendable` probe saw, from any thread.
    final class Recorder<Value: Sendable>: Sendable {
        private let values = Mutex<[Value]>([])
        func record(_ value: Value) { values.withLock { $0.append(value) } }
        var all: [Value] { values.withLock { $0 } }
    }

    @Test("make() reads the bundle and manifest off the main thread, even when awaited from the main actor")
    @MainActor
    func makeRunsOffTheMainThread() async throws {
        let onMain = Recorder<Bool>()
        _ = try await SampleDataCanvasGateway.make(dateProvider: SystemDateProvider(), threadProbe: { onMain.record($0) })
        #expect(onMain.all == [false])
    }

    @Test("updates() starts with the current state, then carries the first snapshot; end() finishes it")
    func updatesThenEnd() async throws {
        let session = SampleSession()
        let updates = await session.updates()
        var iterator = updates.makeAsyncIterator()

        let initial = await iterator.next()
        #expect(initial?.snapshot == nil)
        #expect(initial?.generation == 0)

        await session.refresh(.launch)
        var latest = initial
        // `.bufferingNewest(1)`: whatever the consumer missed, the newest update is what it gets.
        while latest?.snapshot == nil, let next = await iterator.next() { latest = next }
        #expect(latest?.snapshot?.courses.count == 5)
        #expect(latest?.generation == 1)

        await session.end()
        let afterEnd = await iterator.next()
        #expect(afterEnd == nil)
        // After end(), a new subscriber gets an already-finished stream.
        var late = await session.updates().makeAsyncIterator()
        let lateFirst = await late.next()
        #expect(lateFirst == nil)
    }

    @Test("two concurrent refreshes share one run (single-flight)")
    func refreshIsSingleFlight() async throws {
        let calls = Recorder<Int>()
        let session = SampleSession(clock: SystemDateProvider()) {
            calls.record(1)
            return try await SampleDataCanvasGateway.make()
        }
        async let first: Void = session.refresh(.manual)
        async let second: Void = session.refresh(.manual)
        _ = await (first, second)
        #expect(calls.all.count == 1)
    }
}

@Suite("TaskBox: one owned, cancellable task")
struct TaskBoxTests {
    @Test("replace(with:) cancels the task it held; cancel() cancels and drops the current one")
    func replaceCancelsThePrevious() {
        let box = TaskBox()
        let first = Task<Void, Never> { try? await Task.sleep(for: .seconds(60)) }
        box.replace(with: first)
        let second = Task<Void, Never> { try? await Task.sleep(for: .seconds(60)) }
        box.replace(with: second)
        #expect(first.isCancelled)
        #expect(!second.isCancelled)
        box.cancel()
        #expect(second.isCancelled)
        #expect(!box.isHoldingTask)
    }

    @Test("releasing the box cancels its task")
    func releasingTheBoxCancels() {
        let task = Task<Void, Never> { try? await Task.sleep(for: .seconds(60)) }
        var box: TaskBox? = TaskBox()
        box?.replace(with: task)
        box = nil
        #expect(task.isCancelled)
    }
}

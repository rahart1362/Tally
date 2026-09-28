import Synchronization

/// One owned, cancellable `Task` (perf-app-runtime.md §4.6): the compiler-checked replacement for
/// an unchecked (opted-out-of-isolation) stored task. It is `Sendable` and its state sits behind a
/// `Mutex`, so a main-actor model's nonisolated `deinit` may cancel it, and `replace(with:)` from
/// any context is race-free. CI's hygiene job keeps TallyAppleKit free of unchecked stored state.
///
/// - `replace(with:)` cancels the task it held before holding the new one.
/// - `cancel()` cancels and drops the task.
/// - Releasing the box cancels its task, so an owner that is deallocated without an explicit
///   `cancel()` still ends its subscription.
public nonisolated final class TaskBox: Sendable {
    private let task = Mutex<Task<Void, Never>?>(nil)

    public init() {}

    public func replace(with newTask: Task<Void, Never>) {
        let previous = task.withLock { current in
            let old = current
            current = newTask
            return old
        }
        previous?.cancel()
    }

    public func cancel() {
        let previous = task.withLock { current in
            let old = current
            current = nil
            return old
        }
        previous?.cancel()
    }

    /// Whether a task is held (tests).
    var isHoldingTask: Bool { task.withLock { $0 != nil } }

    /// Waits for the held task, if any, to finish (tests).
    func value() async {
        let held = task.withLock { $0 }
        await held?.value
    }

    deinit {
        cancel()
    }
}

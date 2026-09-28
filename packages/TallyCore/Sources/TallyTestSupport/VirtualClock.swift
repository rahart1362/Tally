import Foundation
import Synchronization

/// A `Clock` whose time moves only when something sleeps on it or a test advances it (R-1,
/// resilience.md). `sleep` returns at once: it records the requested wait and jumps `now` to the
/// deadline. A retry loop that backs off for minutes therefore runs in microseconds, and a test can
/// assert on exactly how long it chose to wait and how much time it spent in total.
///
/// Inject it wherever production code takes a `Clock` (`CanvasClient(clock:)`); production uses
/// `ContinuousClock`.
public final class VirtualClock: Clock, Sendable {
    public struct Instant: InstantProtocol, Sendable {
        /// Time since the clock was made.
        public let offset: Duration

        public init(offset: Duration) { self.offset = offset }
        public func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        public func duration(to other: Instant) -> Duration { other.offset - offset }
        public static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleeps: [Duration] = []
    }

    private let state = Mutex(State())

    public init() {}

    public var now: Instant { state.withLock { $0.now } }
    public var minimumResolution: Duration { .zero }

    /// Every wait requested so far, in order (a deadline already past records a non-positive wait).
    public var sleeps: [Duration] { state.withLock { $0.sleeps } }

    /// Time since the clock was made: every sleep plus every `advance`.
    public var elapsed: Duration { state.withLock { $0.now.offset } }

    /// Moves `now` forward, e.g. to model network latency inside a fake transport.
    public func advance(by duration: Duration) {
        state.withLock { $0.now = $0.now.advanced(by: max(duration, .zero)) }
    }

    /// Returns at once, having advanced `now` to `deadline`. Throws `CancellationError`, without
    /// advancing, when the calling task is already cancelled, as `ContinuousClock` does.
    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        try Task.checkCancellation()
        state.withLock { state in
            state.sleeps.append(state.now.duration(to: deadline))
            if state.now < deadline { state.now = deadline }
        }
    }
}

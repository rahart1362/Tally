import Foundation
import Synchronization
import TallyDomain

/// A controllable clock for deterministic tests.
public final class TestClock: DateProviding {
    private let current: Mutex<Date>

    /// Defaults to the synthetic fixtures' anchor instant.
    public init(_ start: Date = Date(timeIntervalSince1970: 1_790_600_400)) { // 2026-09-28T13:00:00Z
        current = Mutex(start)
    }

    public func now() -> Date { current.withLock { $0 } }

    public func advance(by duration: Duration) {
        current.withLock { $0 = $0.addingTimeInterval(duration.timeInterval) }
    }
}

import Synchronization
import TallyDomain

/// A `TallyLogger` that keeps every event in order, for assertions (CS-07).
public final class RecordingLogger: TallyLogger {
    private let recorded = Mutex<[LogEvent]>([])

    public init() {}

    public func log(_ event: LogEvent) { recorded.withLock { $0.append(event) } }

    public var events: [LogEvent] { recorded.withLock { $0 } }
}

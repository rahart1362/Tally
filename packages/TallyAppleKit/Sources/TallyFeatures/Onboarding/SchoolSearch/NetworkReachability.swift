import Dispatch
import Foundation
import Network

/// Whether the device currently has a usable network path (ux-ui.md §3.2.1
/// "Offline" state). Behind a protocol so tests can force either answer
/// without touching real connectivity.
///
/// This is a thin, self-contained wrapper, not a general platform adapter:
/// this work package's `TallyPlatform` scope is "only a new
/// `WebAuthPresenter`" (implementation brief), so a broader connectivity
/// port belongs to whichever later work package needs one elsewhere too.
public protocol NetworkReachabilityChecking: Sendable {
    var isOnline: Bool { get }
}

/// `NWPathMonitor`-backed. `Network` is a system framework (not a
/// third-party dependency), and `NWPathMonitor` is safe to construct and
/// query synchronously off the main thread; the initial `currentPath` is
/// available immediately after `start(queue:)`.
///
/// `nonisolated`: `TallyFeatures` defaults every declaration to `@MainActor`
/// (architecture.md §3.1), but `pathUpdateHandler` is a `@Sendable` closure
/// that `Network` calls on its own dispatch queue, never the main actor.
/// This type opts out of the module default and guards `path` with its own
/// lock instead (`@unchecked Sendable`), the documented escape hatch for
/// wrapping a callback-based system API under SE-0466's per-module isolation.
public nonisolated final class PathMonitorReachability: NetworkReachabilityChecking, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var path: NWPath

    public init() {
        path = monitor.currentPath
        monitor.pathUpdateHandler = { [weak self] newPath in
            guard let self else { return }
            lock.lock(); self.path = newPath; lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "dev.tally-app.tally.reachability"))
    }

    deinit { monitor.cancel() }

    public var isOnline: Bool {
        lock.lock(); defer { lock.unlock() }
        return path.status == .satisfied
    }
}

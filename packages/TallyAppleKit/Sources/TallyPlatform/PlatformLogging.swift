import Foundation
import os

/// Platform log events. No case carries free-form text or student content:
/// "Privacy enforced by types" (architecture.md §3.1) and implementation
/// brief rule 3 ("Never log student content").
public enum PlatformLogEvent: Sendable {
    case appLaunch
    /// The system invoked the registered `.appRefresh` background task.
    case backgroundRefreshInvoked
}

public protocol TallyPlatformLogger: Sendable {
    func log(_ event: PlatformLogEvent)
}

/// `os.Logger`-backed adapter. Construction performs no I/O — `Logger.init`
/// only stores the subsystem/category strings — so it is safe to build
/// inside `AppEnvironment.live()` (architecture.md §3.1: "pure construction,
/// no I/O").
public struct OSLogPlatformLogger: TallyPlatformLogger {
    private let logger: Logger

    public init(subsystem: String = Bundle.main.bundleIdentifier ?? "dev.tally-app.tally") {
        logger = Logger(subsystem: subsystem, category: "platform")
    }

    public func log(_ event: PlatformLogEvent) {
        switch event {
        case .appLaunch:
            logger.info("app_launch")
        case .backgroundRefreshInvoked:
            logger.info("background_refresh_invoked")
        }
    }
}

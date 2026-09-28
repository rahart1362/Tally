#if DEBUG
import Darwin
import Dispatch
import Foundation
import os
import Synchronization
import TallyDomain

/// DEBUG-only main-thread hang detector (perf-app-runtime.md §5.1). It never ships: the whole
/// file compiles only in Debug builds.
///
/// A dedicated `Thread` at `.userInteractive` (never the cooperative pool, which main-actor-heavy
/// code can starve) posts a heartbeat to the main queue every `pingInterval`. The main queue
/// stamps the time it ran the heartbeat. When the newest stamp is older than the threshold, the
/// main run loop has not serviced events for that long: Apple's definition of a hang (tools report
/// from 250 ms, `TallyConfig.mainThreadHangThreshold`).
///
/// Modes come from `TALLY_MAIN_THREAD_WATCHDOG` (`Mode.parse`):
/// - `fatal:<ms>` — UI tests (`TallyUITestCase`): `fatalError("MAIN-THREAD HANG …")` from the
///   watchdog thread, so the crash report holds the main thread's live backtrace.
/// - `report:<ms>` — the DEBUG default: an os_log fault and a signpost event.
/// - `off`, or any value when a debugger is attached (a paused debugger is not a hang).
///
/// Until `endLaunchGrace()` (the first root view's `.task`), the threshold is
/// `TallyConfig.launchHangThreshold` instead.
public final class MainThreadWatchdog: Sendable {
    public enum Mode: Equatable, Sendable {
        case fatal(Duration)
        case report(Duration)
        case off

        public static let environmentKey = "TALLY_MAIN_THREAD_WATCHDOG"

        /// Pure, so every mode is unit-testable. A missing or malformed value falls back to the
        /// DEBUG default, `report` at `TallyConfig.mainThreadHangThreshold`.
        public static func parse(_ value: String?, debuggerAttached: Bool) -> Mode {
            if debuggerAttached { return .off }
            let fallback = Mode.report(TallyConfig.mainThreadHangThreshold)
            guard let value, !value.isEmpty else { return fallback }
            if value == "off" { return .off }
            let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let milliseconds = Int(parts[1]), milliseconds > 0 else { return fallback }
            switch parts[0] {
            case "fatal": return .fatal(.milliseconds(milliseconds))
            case "report": return .report(.milliseconds(milliseconds))
            default: return fallback
            }
        }
    }

    /// The process-wide instance `arm()` starts, or `nil` when the mode is `.off`.
    private static let shared: MainThreadWatchdog? = {
        let mode = Mode.parse(ProcessInfo.processInfo.environment[Mode.environmentKey],
                              debuggerAttached: isDebuggerAttached())
        switch mode {
        case .off:
            return nil
        case .fatal(let threshold):
            return MainThreadWatchdog(threshold: threshold) { stalled in
                fatalError("MAIN-THREAD HANG ≥ \(threshold.wholeMilliseconds) ms: the main run loop has not serviced events for \(stalled.wholeMilliseconds) ms")
            }
        case .report(let threshold):
            return MainThreadWatchdog(threshold: threshold) { stalled in
                let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.tally-app.tally", category: "watchdog")
                logger.fault("main_thread_hang stalled_ms=\(stalled.wholeMilliseconds, privacy: .public)")
                let signposter = OSSignposter(logger: logger)
                signposter.emitEvent("MainThreadHang", "stalled_ms=\(stalled.wholeMilliseconds, privacy: .public)")
            }
        }
    }()

    /// Starts the process-wide watchdog in the mode the environment asks for. Idempotent.
    public static func arm() {
        shared?.start()
    }

    /// The first root view's `.task` ran: switch from the launch threshold to the hang threshold.
    public static func endLaunchGrace() {
        shared?.endLaunchGrace()
    }

    private let threshold: Duration
    private let launchThreshold: Duration
    private let pingInterval: Duration
    private let checkInterval: Duration
    private let onHang: @Sendable (Duration) -> Void
    /// `DispatchTime` uptime nanoseconds of the last heartbeat the main queue ran.
    private let lastBeat = Atomic<UInt64>(0)
    private let inLaunchGrace = Atomic<Bool>(true)
    private let started = Atomic<Bool>(false)
    private let stopped = Atomic<Bool>(false)

    /// - Parameters:
    ///   - threshold: how long the main queue may go without running a heartbeat before `onHang`.
    ///   - launchThreshold: the threshold until `endLaunchGrace()`.
    ///   - onHang: called on the watchdog thread with the stall so far, once per hang.
    public init(
        threshold: Duration,
        launchThreshold: Duration = TallyConfig.launchHangThreshold,
        pingInterval: Duration = .milliseconds(50),
        checkInterval: Duration = .milliseconds(10),
        onHang: @escaping @Sendable (Duration) -> Void
    ) {
        self.threshold = threshold
        self.launchThreshold = launchThreshold
        self.pingInterval = pingInterval
        self.checkInterval = checkInterval
        self.onHang = onHang
    }

    public func start() {
        guard !started.exchange(true, ordering: .relaxed) else { return }
        lastBeat.store(Self.uptimeNanoseconds(), ordering: .relaxed)
        let thread = Thread { [self] in self.watch() }
        thread.name = "dev.tally-app.tally.main-thread-watchdog"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    public func endLaunchGrace() {
        inLaunchGrace.store(false, ordering: .relaxed)
    }

    /// Ends the watchdog thread within one `checkInterval` (tests; the app's instance never stops).
    public func stop() {
        stopped.store(true, ordering: .relaxed)
    }

    private func watch() {
        var lastPing: UInt64 = 0
        var reportedThisHang = false
        let pingNanos = Self.nanoseconds(pingInterval)
        while !stopped.load(ordering: .relaxed) {
            let now = Self.uptimeNanoseconds()
            if now &- lastPing >= pingNanos {
                lastPing = now
                DispatchQueue.main.async { [self] in
                    lastBeat.store(Self.uptimeNanoseconds(), ordering: .relaxed)
                }
            }
            let beat = lastBeat.load(ordering: .relaxed)
            let stalled = now > beat ? now - beat : 0
            let limit = Self.nanoseconds(inLaunchGrace.load(ordering: .relaxed) ? launchThreshold : threshold)
            if stalled > limit {
                if !reportedThisHang {
                    reportedThisHang = true
                    onHang(.nanoseconds(Int64(clamping: stalled)))
                }
            } else {
                reportedThisHang = false
            }
            Thread.sleep(forTimeInterval: checkInterval.timeInterval)
        }
    }

    private static func uptimeNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private static func nanoseconds(_ duration: Duration) -> UInt64 {
        let (seconds, attoseconds) = duration.components
        return UInt64(clamping: seconds) &* 1_000_000_000 &+ UInt64(clamping: attoseconds / 1_000_000_000)
    }

    /// `P_TRACED` on this process: a debugger (Xcode, lldb) is attached.
    private static func isDebuggerAttached() -> Bool {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return false }
        return (info.kp_proc.p_flag & P_TRACED) != 0
    }
}

extension Duration {
    /// Whole milliseconds, for log and crash messages.
    fileprivate var wholeMilliseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}
#endif

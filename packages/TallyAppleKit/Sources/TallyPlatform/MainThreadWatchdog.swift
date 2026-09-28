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
/// **Phases.** The app is *launching* until the first root view's `.task` has run
/// (`firstRootTaskDidRun()`) and the main thread has then stayed responsive for
/// `TallyConfig.launchSettleWindow`; after that it is *interactive*. A launch-phase stall is a
/// hang past `TallyConfig.launchHangThreshold` and is only ever logged: CI measured Debug launches
/// on the simulator stalling the main thread for 1.0-1.65 s (run 36368473854), and up to 3.9 s
/// after launch in first-render type resolution and XCUITest's accessibility attach, after the
/// first `.task` (run 36367196647), never in Tally's own logic. Launch speed has its own budget
/// and metric (`warmStartBudget`, perf-app-runtime.md §7 step 8). An interactive stall is a hang
/// past `mainThreadHangThreshold` (250 ms), the watchdog's real job.
///
/// **Modes** come from `TALLY_MAIN_THREAD_WATCHDOG` (`Mode.parse`):
/// - `fatal:<ms>` — an interactive hang past `<ms>` logs a fault, then `fatalError("MAIN-THREAD
///   HANG …")` from the watchdog thread, so the crash report holds the main thread's backtrace.
/// - `report:<ms>` — the DEBUG default, and UI tests' mode until the fatal threshold is
///   calibrated (`TallyUITestCase`): a fault and a signpost event.
/// - `off`, or any value when a debugger is attached (a paused debugger is not a hang).
///
/// In every mode, each stall longer than the hang threshold is also logged when it ends, with its
/// full length and phase (category `watchdog`); CI prints those lines after the UI tests.
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

    /// One main-thread stall longer than the hang threshold.
    public struct Stall: Equatable, Sendable {
        public enum Phase: String, Equatable, Sendable {
            case launch, interactive
        }

        /// How long the main thread had gone without running a heartbeat (so far, for `.hang`).
        public let duration: Duration
        public let phase: Phase
        /// When the stall was observed, measured from `start()`.
        public let sinceStart: Duration

        public init(duration: Duration, phase: Phase, sinceStart: Duration) {
            self.duration = duration
            self.phase = phase
            self.sinceStart = sinceStart
        }
    }

    public enum Event: Equatable, Sendable {
        /// A stall crossed its phase's threshold. Sent once per stall, while it is still going.
        case hang(Stall)
        /// A stall longer than the hang threshold ended; `duration` is its full length.
        case stallEnded(Stall)
    }

    /// The process-wide instance `arm()` starts, or `nil` when the mode is `.off`.
    private static let shared: MainThreadWatchdog? = {
        let mode = Mode.parse(ProcessInfo.processInfo.environment[Mode.environmentKey],
                              debuggerAttached: isDebuggerAttached())
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.tally-app.tally", category: "watchdog")
        switch mode {
        case .off:
            return nil
        case .fatal(let threshold), .report(let threshold):
            let modeName = if case .fatal = mode { "fatal" } else { "report" }
            return MainThreadWatchdog(threshold: threshold) { event in
                let text = "mode=\(modeName) " + MainThreadWatchdog.describe(event)
                if MainThreadWatchdog.isFatal(event, in: mode) {
                    logger.fault("main_thread_hang_fatal \(text, privacy: .public)")
                    fatalError("MAIN-THREAD HANG ≥ \(threshold.wholeMilliseconds) ms: \(text)")
                }
                switch event {
                case .hang:
                    logger.fault("main_thread_hang \(text, privacy: .public)")
                    OSSignposter(logger: logger).emitEvent("MainThreadHang", "\(text, privacy: .public)")
                case .stallEnded:
                    logger.notice("main_thread_stall \(text, privacy: .public)")
                }
            }
        }
    }()

    /// Whether `event` crashes the process in `mode`: only an *interactive* hang in `.fatal` mode.
    /// A launch-phase hang is logged, never fatal: a Debug launch on the CI simulator stalls the
    /// main thread for 1.0-1.65 s (run 36368473854), and launch speed has its own metric.
    public static func isFatal(_ event: Event, in mode: Mode) -> Bool {
        guard case .fatal = mode, case .hang(let stall) = event else { return false }
        return stall.phase == .interactive
    }

    /// Starts the process-wide watchdog in the mode the environment asks for. Idempotent.
    public static func arm() {
        shared?.start()
    }

    /// The first root view's `.task` ran: launch ends once the main thread then stays responsive
    /// for `TallyConfig.launchSettleWindow`.
    public static func firstRootTaskDidRun() {
        shared?.firstRootTaskDidRun()
    }

    /// `phase=interactive ms=312 since_start_ms=5120`: what the log lines and the crash carry.
    static func describe(_ event: Event) -> String {
        let stall: Stall
        switch event {
        case .hang(let hang): stall = hang
        case .stallEnded(let ended): stall = ended
        }
        return "phase=\(stall.phase.rawValue) ms=\(stall.duration.wholeMilliseconds) since_start_ms=\(stall.sinceStart.wholeMilliseconds)"
    }

    private let threshold: Duration
    private let stallLogThreshold: Duration
    private let launchThreshold: Duration
    private let settleWindow: Duration
    private let pingInterval: Duration
    private let checkInterval: Duration
    private let onEvent: @Sendable (Event) -> Void
    /// `DispatchTime` uptime nanoseconds of the last heartbeat the main queue ran.
    private let lastBeat = Atomic<UInt64>(0)
    private let firstRootTaskRan = Atomic<Bool>(false)
    private let started = Atomic<Bool>(false)
    private let stopped = Atomic<Bool>(false)

    /// - Parameters:
    ///   - threshold: after launch, how long the main queue may go without running a heartbeat
    ///     before a `.hang` (fatal in `.fatal` mode).
    ///   - stallLogThreshold: every stall longer than this is sent as `.stallEnded`, in both
    ///     phases, whatever `threshold` is (so a calibrated, higher fatal threshold still logs
    ///     every 250 ms hang).
    ///   - launchThreshold: the `.hang` limit while the app is launching (logged, never fatal).
    ///   - settleWindow: how long the main thread must stay responsive, after
    ///     `firstRootTaskDidRun()`, for launch to end.
    ///   - onEvent: called on the watchdog thread.
    public init(
        threshold: Duration,
        stallLogThreshold: Duration = TallyConfig.mainThreadHangThreshold,
        launchThreshold: Duration = TallyConfig.launchHangThreshold,
        settleWindow: Duration = TallyConfig.launchSettleWindow,
        pingInterval: Duration = .milliseconds(50),
        checkInterval: Duration = .milliseconds(10),
        onEvent: @escaping @Sendable (Event) -> Void
    ) {
        self.threshold = threshold
        self.stallLogThreshold = stallLogThreshold
        self.launchThreshold = launchThreshold
        self.settleWindow = settleWindow
        self.pingInterval = pingInterval
        self.checkInterval = checkInterval
        self.onEvent = onEvent
    }

    public func start() {
        guard !started.exchange(true, ordering: .relaxed) else { return }
        lastBeat.store(Self.uptimeNanoseconds(), ordering: .relaxed)
        let thread = Thread { [self] in self.watch() }
        thread.name = "dev.tally-app.tally.main-thread-watchdog"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    public func firstRootTaskDidRun() {
        firstRootTaskRan.store(true, ordering: .relaxed)
    }

    /// Ends the watchdog thread within one `checkInterval` (tests; the app's instance never stops).
    public func stop() {
        stopped.store(true, ordering: .relaxed)
    }

    /// Runs on the watchdog thread only, so its bookkeeping is plain local state.
    private func watch() {
        let startedAt = Self.uptimeNanoseconds()
        let pingNanos = Self.nanoseconds(pingInterval)
        let hangNanos = Self.nanoseconds(threshold)
        let logNanos = min(Self.nanoseconds(stallLogThreshold), hangNanos)
        let launchNanos = Self.nanoseconds(launchThreshold)
        let settleNanos = Self.nanoseconds(settleWindow)
        var lastPing: UInt64 = 0
        var launching = true
        var responsiveSince: UInt64?
        var currentStall: (longest: UInt64, phase: Stall.Phase, at: UInt64)?
        var reportedCurrentStall = false

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

            if stalled > logNanos {
                let phase: Stall.Phase = launching ? .launch : .interactive
                currentStall = (longest: max(currentStall?.longest ?? 0, stalled),
                                phase: currentStall?.phase ?? phase, at: currentStall?.at ?? now)
                responsiveSince = nil
                if !reportedCurrentStall, stalled > (launching ? launchNanos : hangNanos) {
                    reportedCurrentStall = true
                    onEvent(.hang(Stall(duration: .nanoseconds(Int64(clamping: stalled)), phase: phase,
                                        sinceStart: .nanoseconds(Int64(clamping: now - startedAt)))))
                }
            } else {
                if let stall = currentStall {
                    onEvent(.stallEnded(Stall(duration: .nanoseconds(Int64(clamping: stall.longest)), phase: stall.phase,
                                              sinceStart: .nanoseconds(Int64(clamping: stall.at - startedAt)))))
                    currentStall = nil
                }
                reportedCurrentStall = false
                if launching, firstRootTaskRan.load(ordering: .relaxed) {
                    let since = responsiveSince ?? now
                    responsiveSince = since
                    if now - since >= settleNanos { launching = false }
                }
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

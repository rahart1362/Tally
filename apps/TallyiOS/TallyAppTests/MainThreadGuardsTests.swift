import Foundation
import Synchronization
import Testing
import TallyDomain
import TallyPlatform
@testable import TallyFeatures

/// perf-app-runtime.md §7 step 4: the DEBUG main-thread watchdog (modes and detection) and the
/// main-actor stall budget on the sample-data path. The watchdog exists only in Debug builds, so
/// its tests do too; the stall budget runs in both (Debug in `ios-build`, Release in `ios-perf`).
@Suite("Main-thread guards: watchdog and main-actor stall budget", .serialized)
struct MainThreadGuardsTests {
    #if DEBUG
    // MARK: - Watchdog modes

    @Test("TALLY_MAIN_THREAD_WATCHDOG parses into a mode; a debugger turns it off")
    func watchdogModes() {
        typealias Mode = MainThreadWatchdog.Mode
        let standard = Mode.report(TallyConfig.mainThreadHangThreshold)
        #expect(Mode.parse("fatal:250", debuggerAttached: false) == .fatal(.milliseconds(250)))
        #expect(Mode.parse("report:400", debuggerAttached: false) == .report(.milliseconds(400)))
        #expect(Mode.parse("off", debuggerAttached: false) == .off)
        #expect(Mode.parse(nil, debuggerAttached: false) == standard)
        #expect(Mode.parse("", debuggerAttached: false) == standard)
        #expect(Mode.parse("fatal", debuggerAttached: false) == standard)
        #expect(Mode.parse("fatal:0", debuggerAttached: false) == standard)
        #expect(Mode.parse("panic:250", debuggerAttached: false) == standard)
        #expect(Mode.parse("fatal:250", debuggerAttached: true) == .off)
    }

    @Test("only an interactive hang in fatal mode crashes; launch hangs, ended stalls and report mode never do")
    func onlyInteractiveHangsAreFatal() {
        typealias Watchdog = MainThreadWatchdog
        let fatal = Watchdog.Mode.fatal(TallyConfig.mainThreadHangThreshold)
        let report = Watchdog.Mode.report(TallyConfig.mainThreadHangThreshold)
        func stall(_ phase: Watchdog.Stall.Phase) -> Watchdog.Stall {
            Watchdog.Stall(duration: .milliseconds(1500), phase: phase, sinceStart: .seconds(5))
        }
        #expect(Watchdog.isFatal(.hang(stall(.interactive)), in: fatal))
        #expect(!Watchdog.isFatal(.hang(stall(.launch)), in: fatal))
        #expect(!Watchdog.isFatal(.stallEnded(stall(.interactive)), in: fatal))
        #expect(!Watchdog.isFatal(.hang(stall(.interactive)), in: report))
        #expect(!Watchdog.isFatal(.hang(stall(.interactive)), in: .off))
    }

    // MARK: - Watchdog detection

    /// Collects the events a watchdog sends, from its own thread.
    private final class EventLog: Sendable {
        private let events = Mutex<[MainThreadWatchdog.Event]>([])
        func record(_ event: MainThreadWatchdog.Event) { events.withLock { $0.append(event) } }
        var hangs: [MainThreadWatchdog.Stall] {
            events.withLock { all in
                all.compactMap { event -> MainThreadWatchdog.Stall? in
                    if case .hang(let stall) = event { return stall }
                    return nil
                }
            }
        }
        var ended: [MainThreadWatchdog.Stall] {
            events.withLock { all in
                all.compactMap { event -> MainThreadWatchdog.Stall? in
                    if case .stallEnded(let stall) = event { return stall }
                    return nil
                }
            }
        }
    }

    @Test("after launch settles: an idle main thread is never reported; a 600 ms block is a hang, reported once")
    @MainActor
    func watchdogReportsAnInteractiveHang() async throws {
        let log = EventLog()
        let threshold = TallyConfig.mainThreadHangThreshold
        let watchdog = MainThreadWatchdog(threshold: threshold, settleWindow: .milliseconds(100)) { log.record($0) }
        watchdog.start()
        defer { watchdog.stop() }
        watchdog.firstRootTaskDidRun()

        try await Task.sleep(for: .milliseconds(500)) // idle: heartbeats run, launch settles
        #expect(log.hangs.isEmpty, "false positive while the main thread was idle: \(log.hangs)")

        Self.blockCurrentThread(seconds: 0.6) // the main thread itself, like a hang would
        try await Task.sleep(for: .milliseconds(300))
        let hangs = log.hangs.filter { $0.phase == .interactive }
        #expect(hangs.count == 1, "one hang, reported once: \(log.hangs)")
        #expect(hangs.allSatisfy { $0.duration > threshold }, "\(hangs)")
        let blocked = log.ended.filter { $0.duration >= .milliseconds(500) }
        #expect(blocked.count == 1 && blocked.first?.phase == .interactive, "the full stall is logged when it ends: \(log.ended)")
    }

    @Test("while launching, a 600 ms block is under the launch threshold: logged when it ends, never a hang")
    @MainActor
    func launchGraceCoversAFirstRenderStall() async throws {
        let log = EventLog()
        // Launch never settles in this test: `firstRootTaskDidRun()` is never called.
        let watchdog = MainThreadWatchdog(threshold: TallyConfig.mainThreadHangThreshold) { log.record($0) }
        watchdog.start()
        defer { watchdog.stop() }

        Self.blockCurrentThread(seconds: 0.6)
        try await Task.sleep(for: .milliseconds(300))
        #expect(log.hangs.isEmpty, "a launch-phase stall under launchHangThreshold is not a hang: \(log.hangs)")
        let blocked = log.ended.filter { $0.duration >= .milliseconds(500) }
        #expect(blocked.count == 1 && blocked.first?.phase == .launch, "\(log.ended)")
    }

    @Test("with a fatal threshold above 250 ms, a shorter interactive stall is logged at full length, not a hang")
    @MainActor
    func stallsUnderACalibratedThresholdAreLoggedNotHangs() async throws {
        let log = EventLog()
        let watchdog = MainThreadWatchdog(threshold: .seconds(2), settleWindow: .milliseconds(100)) { log.record($0) }
        watchdog.start()
        defer { watchdog.stop() }
        watchdog.firstRootTaskDidRun()

        try await Task.sleep(for: .milliseconds(500)) // launch settles
        Self.blockCurrentThread(seconds: 0.6)
        try await Task.sleep(for: .milliseconds(300))
        #expect(log.hangs.isEmpty, "600 ms is under the 2 s threshold: \(log.hangs)")
        let blocked = log.ended.filter { $0.duration >= .milliseconds(500) }
        #expect(blocked.count == 1 && blocked.first?.phase == .interactive, "\(log.ended)")
    }

    /// Synchronous on purpose: `Thread.sleep` is unavailable from async contexts.
    private static func blockCurrentThread(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
    #endif

    // MARK: - Main-actor stall budget

    /// A Debug build is held to `mainActorStallBudget`, a Release build to half of it
    /// (perf-app-runtime.md §5.2: < 50 ms Debug, < 25 ms Release).
    static var stallBudget: Duration {
        #if DEBUG
        TallyConfig.mainActorStallBudget
        #else
        TallyConfig.mainActorStallBudget / 2
        #endif
    }

    /// The median of 5 entries, so one scheduling hiccup on a shared CI simulator cannot fail the
    /// test, while main-actor work that stalls on every entry always does.
    @Test("sample entry and its first refresh never stall the main actor past the budget")
    @MainActor
    func sampleEntryStaysUnderTheStallBudget() async throws {
        var stalls: [Duration] = []
        for _ in 0..<5 {
            let probe = MainActorStallProbe()
            probe.start()
            try await Task.sleep(for: .milliseconds(20)) // the ticker is running before the work starts
            let model = try SampleDataModel.live()
            await model.refresh()
            stalls.append(await probe.stop())
            #expect(model.snapshot?.courses.count == 5)
        }
        let median = stalls.sorted()[stalls.count / 2]
        #expect(median < Self.stallBudget, "median main-actor stall \(median) ≥ \(Self.stallBudget); all: \(stalls)")
    }
}

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

    // MARK: - Watchdog detection

    /// Collects the stalls a watchdog reports, from its own thread.
    private final class HangLog: Sendable {
        private let stalls = Mutex<[Duration]>([])
        func record(_ stall: Duration) { stalls.withLock { $0.append(stall) } }
        var recorded: [Duration] { stalls.withLock { $0 } }
    }

    @Test("an idle main thread is never reported; a 600 ms block is reported once, past the threshold")
    @MainActor
    func watchdogReportsABlockedMainThread() async throws {
        let log = HangLog()
        let threshold = TallyConfig.mainThreadHangThreshold
        let watchdog = MainThreadWatchdog(threshold: threshold, launchThreshold: threshold) { log.record($0) }
        watchdog.start()
        defer { watchdog.stop() }

        try await Task.sleep(for: .milliseconds(400)) // idle: heartbeats run
        #expect(log.recorded.isEmpty, "false positive while the main thread was idle: \(log.recorded)")

        Self.blockCurrentThread(seconds: 0.6) // the main thread itself, like a hang would
        try await Task.sleep(for: .milliseconds(200))
        let recorded = log.recorded
        #expect(recorded.count == 1, "one hang, reported once: \(recorded)")
        #expect(recorded.allSatisfy { $0 > threshold }, "\(recorded)")
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

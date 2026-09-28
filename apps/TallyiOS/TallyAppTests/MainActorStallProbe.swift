import Foundation

/// perf-app-runtime.md §5.2: measures how long the main actor was unavailable while some work
/// ran. A main-actor ticker sleeps `tick` at a time; any extra time between two ticks is time the
/// main actor spent on something else, so the longest such gap is the longest main-actor stall.
///
///     let probe = MainActorStallProbe()
///     probe.start()
///     await workUnderTest()
///     let longest = await probe.stop()
@MainActor
final class MainActorStallProbe {
    static let tick: Duration = .milliseconds(5)

    private(set) var longestStall: Duration = .zero
    private var ticker: Task<Void, Never>?

    func start() {
        longestStall = .zero
        let clock = ContinuousClock()
        ticker = Task { @MainActor in
            var last = clock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tick)
                let now = clock.now
                let stall = now - last - Self.tick
                if stall > self.longestStall { self.longestStall = stall }
                last = now
            }
        }
    }

    /// Stops the ticker and returns the longest stall it saw.
    func stop() async -> Duration {
        ticker?.cancel()
        await ticker?.value
        ticker = nil
        return longestStall
    }
}

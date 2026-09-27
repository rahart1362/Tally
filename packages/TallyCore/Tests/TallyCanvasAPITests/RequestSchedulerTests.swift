import Foundation
import Synchronization
import Testing
import TallyTestSupport
@testable import TallyCanvasAPI

/// Counts how many operations run at once.
private final class ConcurrencyProbe: Sendable {
    private let state = Mutex((current: 0, peak: 0))
    var peak: Int { state.withLock { $0.peak } }
    func enter() { state.withLock { $0.current += 1; $0.peak = max($0.peak, $0.current) } }
    func leave() { state.withLock { $0.current -= 1 } }
}

@Suite("RequestScheduler and backoff")
struct RequestSchedulerTests {
    private func response(remaining: Double?) -> HTTPResponse {
        var headers = HTTPHeaders()
        headers["X-Rate-Limit-Remaining"] = remaining.map { String($0) }
        return HTTPResponse(status: 200, headers: headers)
    }

    private func burst(_ scheduler: RequestScheduler, count: Int, remaining: Double?, probe: ConcurrencyProbe) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<count {
                group.addTask {
                    _ = try await scheduler.perform {
                        probe.enter()
                        try await Task.sleep(for: .milliseconds(15))
                        probe.leave()
                        return self.response(remaining: remaining)
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    @Test func neverMoreThanThreeInFlight() async throws {
        let probe = ConcurrencyProbe()
        try await burst(RequestScheduler(maxConcurrent: 3), count: 20, remaining: 700, probe: probe)
        #expect(probe.peak == 3)
    }

    @Test func lowQuotaDropsToOneThenRecovers() async throws {
        let scheduler = RequestScheduler(maxConcurrent: 3, lowQuotaThreshold: 100)
        _ = try await scheduler.perform { self.response(remaining: 40) }
        #expect(await scheduler.currentLimit == 1)
        let low = ConcurrencyProbe()
        try await burst(scheduler, count: 6, remaining: 40, probe: low)
        #expect(low.peak == 1)
        _ = try await scheduler.perform { self.response(remaining: 650) }
        #expect(await scheduler.currentLimit == 3)
    }

    @Test func cancelledWaiterGivesBackItsSlot() async throws {
        let scheduler = RequestScheduler(maxConcurrent: 1)
        try await scheduler.acquire() // hold the only slot
        let waiter = Task { try await scheduler.acquire() }
        try await Task.sleep(for: .milliseconds(20))
        waiter.cancel()
        await scheduler.release(observed: nil) // hand the slot to the cancelled waiter
        await #expect(throws: CancellationError.self) { try await waiter.value }
        let probe = ConcurrencyProbe()
        try await burst(scheduler, count: 3, remaining: nil, probe: probe) // no leaked slot
        #expect(probe.peak == 1)
    }

    @Test func backoffIsDeterministicBoundedAndBudgeted() {
        let policy = BackoffPolicy(base: .seconds(1), maxDelay: .seconds(8))
        var a = SeededRandom(seed: 42), b = SeededRandom(seed: 42)
        let first = (0..<6).map { policy.delay(attempt: $0, remainingBudget: .seconds(60), using: &a) }
        let second = (0..<6).map { policy.delay(attempt: $0, remainingBudget: .seconds(60), using: &b) }
        #expect(first == second)
        for (attempt, delay) in first.enumerated() {
            let cap = min(Double(1 << attempt), 8.0)
            #expect(delay != nil && delay!.timeInterval <= cap)
        }
        var rng = SeededRandom(seed: 7)
        #expect(policy.delay(attempt: 3, remainingBudget: .zero, using: &rng) == nil)
    }
}

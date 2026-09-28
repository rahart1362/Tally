import Foundation
import Testing
import TallyDomain
import TallyTestSupport
@testable import TallyCanvasAPI

/// R-4 (resilience.md, crash-safety-2.md F-8): `BackoffPolicy` is public with public durations. A
/// negative one made `Double.random(in: 0...ceiling)` trap ("Range requires lowerBound <=
/// upperBound"), and a huge one overflowed the `Int64` milliseconds. Now `base` and `maxDelay`
/// count as 0 below zero and `BackoffPolicy.longestDelay` (1 h) above it, so every delay is in
/// 0...longestDelay.
@Suite("BackoffPolicy: a negative or huge policy never traps (R-4)", .timeLimit(.minutes(TestTimeBudget.minutes(1))))
struct BackoffPolicyBoundsTests {
    @Test(arguments: [
        BackoffPolicy(base: .seconds(-1), maxDelay: .seconds(-8)),
        BackoffPolicy(base: .seconds(-5), maxDelay: .seconds(8)),
        BackoffPolicy(base: .seconds(1), maxDelay: .seconds(-1)),
        BackoffPolicy(base: .seconds(Int64.max), maxDelay: .seconds(Int64.max)),
        BackoffPolicy(base: .seconds(Int64.min), maxDelay: .seconds(Int64.max)),
    ])
    func everyDelayStaysInsideZeroAndTheLongestDelay(_ policy: BackoffPolicy) {
        var rng = SeededRandom(seed: 3)
        let unlimited = Duration.seconds(Int64.max)
        for attempt in [Int.min, -3, 0, 1, 5, 40, Int.max] {
            let delay = policy.delay(attempt: attempt, remainingBudget: unlimited, using: &rng)
            let rateLimitDelay = policy.rateLimitDelay(attempt: attempt, retryAfter: nil, remainingBudget: unlimited, using: &rng)
            for value in [delay, rateLimitDelay] {
                #expect(value.map { $0 >= .zero && $0 <= BackoffPolicy.longestDelay } == true, "attempt \(attempt): \(String(describing: value))")
            }
        }
    }

    /// The same bound also keeps an in-range policy's own behaviour: the production defaults are
    /// untouched (1 s base, 8 s cap).
    @Test func theDefaultPolicyIsUnchanged() {
        var rng = SeededRandom(seed: 9)
        for attempt in 0..<8 {
            let ceiling = min(Duration.seconds(1) * (1 << attempt), .seconds(8))
            let delay = BackoffPolicy().delay(attempt: attempt, remainingBudget: .seconds(60), using: &rng)
            #expect(delay.map { $0 >= .zero && $0 <= ceiling } == true)
        }
    }
}

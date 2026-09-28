import TallyDomain

/// Caps concurrent Canvas requests per account and drops to one at a time
/// when Canvas reports a low quota (architecture §3.3, throttling docs).
public actor RequestScheduler {
    private let normalLimit: Int
    private let lowQuotaThreshold: Double
    private var inFlight = 0
    private var lastRemaining: Double?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(maxConcurrent: Int = TallyConfig.maxConcurrentRequests,
                lowQuotaThreshold: Double = TallyConfig.lowQuotaThreshold) {
        precondition(maxConcurrent >= 1, "maxConcurrent must be at least 1")
        normalLimit = maxConcurrent
        self.lowQuotaThreshold = lowQuotaThreshold
    }

    public var currentLimit: Int {
        guard let remaining = lastRemaining, remaining < lowQuotaThreshold else { return normalLimit }
        return 1
    }

    /// Waits for a slot. Throws `CancellationError` (holding no slot) if the task was cancelled.
    public func acquire() async throws {
        if inFlight < currentLimit {
            inFlight += 1
        } else {
            await withCheckedContinuation { waiters.append($0) } // slot is handed over by release()
        }
        if Task.isCancelled {
            release(observed: nil)
            throw CancellationError()
        }
    }

    public func release(observed info: RateLimitInfo?) {
        if let remaining = info?.remaining { lastRemaining = remaining }
        inFlight -= 1
        while inFlight < currentLimit, !waiters.isEmpty {
            inFlight += 1
            waiters.removeFirst().resume()
        }
    }

    /// Runs `operation` inside a slot, feeding the response's quota headers back.
    public nonisolated func perform(_ operation: @Sendable () async throws -> HTTPResponse) async throws -> HTTPResponse {
        try await acquire()
        do {
            let response = try await operation()
            await release(observed: RateLimitInfo(response))
            return response
        } catch {
            await release(observed: nil)
            throw error
        }
    }
}

/// Exponential backoff, bounded by what is left of the request's budget. `delay` (server errors)
/// uses full jitter; `rateLimitDelay` (rate limits) has a floor and honours `Retry-After`.
public struct BackoffPolicy: Sendable {
    public var base: Duration
    public var maxDelay: Duration

    public init(base: Duration = TallyConfig.backoffBase, maxDelay: Duration = .seconds(8)) {
        self.base = base
        self.maxDelay = maxDelay
    }

    /// Delay before retry number `attempt` (0-based), or nil if it would overrun `remainingBudget`.
    public func delay(attempt: Int, remainingBudget: Duration, using rng: inout some RandomNumberGenerator) -> Duration? {
        let ceiling = ceilingSeconds(attempt: attempt)
        let seconds = Double.random(in: 0...ceiling, using: &rng)
        let delay = Duration.milliseconds(Int64((seconds * 1000).rounded()))
        return delay < remainingBudget ? delay : nil
    }

    /// R-1 (resilience.md): the delay before rate-limit retry number `attempt` (0-based), or nil
    /// when the caller should stop and report the rate limit.
    /// - Exponential with a floor: a random point in the upper half of `min(base · 2^attempt,
    ///   maxDelay)` ("equal jitter"). A retry never follows at once, as full jitter's zero can, and
    ///   each step's floor doubles until `maxDelay`.
    /// - Never sooner than `retryAfter`, the server's own `Retry-After`.
    /// - Nil when the delay would not end inside `remainingBudget`. That includes a `retryAfter`
    ///   longer than the budget: the caller stops rather than sleep past its budget.
    public func rateLimitDelay(attempt: Int, retryAfter: Duration?, remainingBudget: Duration,
                               using rng: inout some RandomNumberGenerator) -> Duration? {
        let ceiling = ceilingSeconds(attempt: attempt)
        let seconds = Double.random(in: (ceiling / 2)...ceiling, using: &rng)
        let backoff = Duration.milliseconds(Int64((seconds * 1000).rounded()))
        let delay = max(backoff, retryAfter ?? .zero)
        return delay < remainingBudget ? delay : nil
    }

    /// `min(base · 2^attempt, maxDelay)` in seconds; the exponent stops growing at 16.
    private func ceilingSeconds(attempt: Int) -> Double {
        min(base.timeInterval * Double(1 << min(attempt, 16)), maxDelay.timeInterval)
    }
}

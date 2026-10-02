import Foundation

/// What started a refresh.
public enum RefreshTrigger: String, Codable, Sendable, CaseIterable {
    case launch, foreground, manual, background, intent
}

/// Why a refresh failed: a category only, never a payload (kit 08).
/// `Error` conformance (WP-B06b addition) lets `CanvasClient`/`CanvasGateway` throw this
/// category directly, so the transport layer and the freshness UI share one vocabulary
/// instead of a parallel error enum that must be kept in sync with it.
///
/// `schoolDisabled` (PAY-10, M3-B2): Canvas rejected Tally itself (`invalid_client`): the school
/// turned off or removed Tally's developer key. Not the student's sign-in, so the tokens and the
/// saved data are kept; the app shows the school-revoked notice while the student is entitled.
public enum RefreshFailure: String, Codable, Sendable, CaseIterable, Error {
    case offline, authExpired, rateLimited, server, contract, unknown, schoolDisabled
}

/// Refresh facts persisted as `refresh-state` (kit 11 §Cache Strategy).
/// Holds no student content.
public struct RefreshRecord: Codable, Equatable, Sendable {
    public private(set) var lastSuccessAt: Date?
    public private(set) var lastAttemptAt: Date?
    public private(set) var lastSource: RefreshTrigger?
    public private(set) var lastFailure: RefreshFailure?
    public private(set) var inFlightSince: Date?

    public init() {}

    public mutating func began(_ trigger: RefreshTrigger, at now: Date) {
        inFlightSince = now
        lastAttemptAt = now
        lastSource = trigger
    }

    /// Records a committed snapshot. Never moves `lastSuccessAt` backwards.
    public mutating func succeeded(dataFetchedAt: Date) {
        lastSuccessAt = max(lastSuccessAt ?? dataFetchedAt, dataFetchedAt)
        lastFailure = nil
        inFlightSince = nil
    }

    public mutating func failed(_ failure: RefreshFailure) {
        lastFailure = failure
        inFlightSince = nil
    }

    /// No refresh survives a relaunch, so a persisted in-flight mark is dropped.
    public func restoredAfterLaunch() -> RefreshRecord {
        var copy = self
        copy.inFlightSince = nil
        return copy
    }
}

/// What the UI shows about data freshness (architecture §3.4, kit 11 copy).
public enum FreshnessState: Equatable, Sendable {
    case noCache
    case fresh(at: Date)
    case refreshing(showing: Date?)
    /// Live refresh exceeded the budget. `showing == nil` means the first
    /// sync is slow: there is no cache yet, so no stale breadcrumb.
    case delayed(showing: Date?)
    case offline(showing: Date?)
    case authExpired(showing: Date?)
    case failed(RefreshFailure, showing: Date?)

    /// Timestamp of the saved data on screen, if any.
    public var showing: Date? {
        switch self {
        case .noCache: nil
        case .fresh(let at): at
        case .refreshing(let s), .delayed(let s), .offline(let s), .authExpired(let s), .failed(_, let s): s
        }
    }

    /// True when saved data is on screen and live data is late or unavailable.
    public var showsStaleBreadcrumb: Bool {
        switch self {
        case .noCache, .fresh, .refreshing: false
        case .delayed, .offline, .authExpired, .failed: showing != nil
        }
    }
}

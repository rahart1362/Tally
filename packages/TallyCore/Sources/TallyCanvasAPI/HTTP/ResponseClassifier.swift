import Foundation
import TallyDomain

/// What a Canvas response means for the client (architecture §3.3, security §3.2).
public enum ResponseClass: Sendable, Equatable {
    case success
    /// 401 with `WWW-Authenticate`: invalid, expired or revoked token. Refresh once, retry once.
    case tokenRejected
    /// 401 without `WWW-Authenticate`: the key lacks a scope. Never refresh.
    case insufficientScope
    /// 429, or 403 whose body says "Rate Limit Exceeded" (Canvas uses both).
    case rateLimited
    case forbidden
    case notFound
    /// 5xx: retried at most twice.
    case serverError
    case unexpected(status: Int)
}

public enum ResponseClassifier {
    /// Only the first bytes of a 403 body are inspected, and they are never logged.
    static let rateLimitProbeBytes = 256

    public static func classify(_ response: HTTPResponse) -> ResponseClass {
        switch response.status {
        case 200..<300: return .success
        case 401: return response.headers["WWW-Authenticate"] == nil ? .insufficientScope : .tokenRejected
        case 429: return .rateLimited
        case 403: return isRateLimitBody(response.body) ? .rateLimited : .forbidden
        case 404: return .notFound
        case 500..<600: return .serverError
        default: return .unexpected(status: response.status)
        }
    }

    /// The refresh-level failure a terminal (non-retried) response produces.
    public static func refreshFailure(for responseClass: ResponseClass) -> RefreshFailure? {
        switch responseClass {
        case .success: nil
        case .tokenRejected: .authExpired
        case .rateLimited: .rateLimited
        case .serverError: .server
        case .insufficientScope, .forbidden, .notFound, .unexpected: .unknown
        }
    }

    private static func isRateLimitBody(_ body: Data) -> Bool {
        let probe = String(decoding: body.prefix(rateLimitProbeBytes), as: UTF8.self)
        return probe.range(of: "rate limit exceeded", options: .caseInsensitive) != nil
    }
}

/// Canvas throttling headers (canvas.instructure.com/doc/api/file.throttling.html).
public struct RateLimitInfo: Sendable, Equatable {
    public let remaining: Double?
    public let cost: Double?

    public init(_ response: HTTPResponse) {
        remaining = response.headers["X-Rate-Limit-Remaining"].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        cost = response.headers["X-Request-Cost"].flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }

    public func isLow(threshold: Double = TallyConfig.lowQuotaThreshold) -> Bool {
        remaining.map { $0 < threshold } ?? false
    }
}

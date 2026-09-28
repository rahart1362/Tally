import Foundation
import TallyCanvasAPI

/// An `HTTPTransport` that answers from a fixed script (R-1, resilience.md): the `n`th request gets
/// the `n`th response, and every request after the script runs out gets its last response, so
/// `[rateLimited]` is a persistent 429. It records every request, and it can charge each one
/// `latency` on a `VirtualClock`, so a test sees both how many requests a retry loop made and how
/// much (virtual) time it spent.
public actor ScriptedTransport: HTTPTransport {
    private let script: [HTTPResponse]
    private let clock: VirtualClock?
    private let latency: Duration
    private var sent: [HTTPRequest] = []

    public init(_ script: [HTTPResponse], clock: VirtualClock? = nil, latency: Duration = .zero) {
        self.script = script
        self.clock = clock
        self.latency = latency
    }

    public var requestCount: Int { sent.count }
    public func requests() -> [HTTPRequest] { sent }

    public func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
        sent.append(request)
        clock?.advance(by: latency)
        guard let last = script.last else { return HTTPResponse(status: 404) }
        return sent.count <= script.count ? script[sent.count - 1] : last
    }

    // MARK: - Canned responses

    /// Canvas's 429 (`fixtures/canvas/errors/429-rate-limit-exceeded`), with optional
    /// `Retry-After` and `Date` headers.
    public static func rateLimited(retryAfter: String? = nil, date: String? = nil) -> HTTPResponse {
        var headers = HTTPHeaders(["Content-Type": "text/plain; charset=utf-8", "X-Rate-Limit-Remaining": "0.0"])
        if let retryAfter { headers["Retry-After"] = retryAfter }
        if let date { headers["Date"] = date }
        return HTTPResponse(status: 429, headers: headers, body: Data("429 Too Many Requests (Rate Limit Exceeded)".utf8))
    }

    /// Canvas's other rate-limit shape: a 403 whose body says "Rate Limit Exceeded".
    public static func rateLimitedForbidden() -> HTTPResponse {
        HTTPResponse(status: 403, headers: HTTPHeaders(["Content-Type": "text/plain; charset=utf-8", "X-Rate-Limit-Remaining": "0.0"]),
                     body: Data("403 Forbidden (Rate Limit Exceeded)".utf8))
    }

    /// A 200 with a JSON body.
    public static func ok(_ json: String) -> HTTPResponse {
        HTTPResponse(status: 200, headers: HTTPHeaders(["Content-Type": "application/json"]), body: Data(json.utf8))
    }
}

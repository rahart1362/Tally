import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import TallyCanvasAPI

/// A real `URLSession`-backed `HTTPTransport`, built only because the shipping
/// `URLSessionTransport` (`packages/TallyAppleKit/Sources/TallyPlatform/URLSessionTransport.swift`)
/// cannot be linked into a Linux SwiftPM test target: that target's own `TallyPlatform`
/// product depends on `TallyFeatures` (for `WebAuthPresenter`, `TallyPlatform.swift` dependency
/// list) which depends on `TallyDesignSystem`, which unconditionally `import SwiftUI`
/// (e.g. `packages/TallyAppleKit/Sources/TallyDesignSystem/AccessibilityReflow.swift:1`).
/// Confirmed with a trial build in the pinned `swift:6.4.0-noble` container (adding
/// `.product(name: "TallyPlatform", package: "TallyAppleKit")` to a throwaway Linux test
/// target): `error: no such module 'SwiftUI'`. See docs/pmo/reviews/live1-report.md finding
/// F1 — not fixed here (tests only; the fix is a product-code split of `TallyPlatform`).
///
/// This is still a **real** `URLSession`, issuing real sockets to live Canvas — never a
/// fixture, stub, or canned response — so everything above the transport (`CanvasClient`'s
/// auth-attach/retry/backoff, the DTO decoders, the mappers, `LiveCanvasGateway`'s snapshot
/// assembly) runs its true production code path. What it deliberately does **not** reproduce
/// from the shipping transport: the per-redirect `Authorization`-stripping delegate and the
/// streamed response-size cap (`TransportTaskDelegate`) — neither applies here (this harness
/// never redirects cross-host, and Canvas's live responses are well under
/// `TallyConfig.maxResponseBodyBytes`), so a completion-handler `URLSession` task is enough.
///
/// - `forceScheme`/`forcePort`: **findings F2 and F3** (live1-report.md). F2:
///   `CanvasClient.url(path:query:)` (`Sources/TallyCanvasAPI/Client/CanvasClient.swift:68`)
///   hardcodes `components.scheme = "https"` with no override, which is correct for every real
///   school (production Canvas is always TLS) but means `CanvasClient` cannot address this e2e
///   stack's plain-HTTP origin (`curl https://127.0.0.1:8790/health_check` fails the TLS
///   handshake; `http://` succeeds — RUNBOOK.md). F3: that same function never sets
///   `components.port` at all — there is no way to give `CanvasClient` a custom port — and its
///   `components.url!` force-unwrap (disabled-lint comment: "scheme/host/path are always
///   well-formed here") traps instead of throwing the moment `host` itself isn't a bare
///   hostname (confirmed: this harness crashed with "Unexpectedly found nil while unwrapping an
///   Optional value" at that exact line when it first tried `host: "127.0.0.1:8790"`). Rather
///   than patch product code for a dev-only mismatch, this transport rewrites the scheme and
///   restores the port `CanvasClient` was never told about, on the request's `URL`, just before
///   the real socket call — the one deliberate, disclosed deviation in this harness's whole
///   request path; `LiveCanvasEnvironment.Config` keeps `host` itself bare for exactly this
///   reason.
public final class LiveURLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession
    private let forceScheme: String
    private let forcePort: Int?

    public init(forceScheme: String, forcePort: Int? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
        self.forceScheme = forceScheme
        self.forcePort = forcePort
    }

    public func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
        do {
            let urlRequest = Self.urlRequest(for: request, forceScheme: forceScheme, forcePort: forcePort)
            let (data, response) = try await send(urlRequest)
            guard let http = response as? HTTPURLResponse else { throw TransportError.other }
            var headers = Self.headers(from: http)
            // Item 5 (LIVE-3) companion fix: `CanvasClient.fetchAllPages` now THROWS on a `next`
            // link `PageURLPolicy` rejects (not https, a foreign host, or embedded credentials)
            // instead of silently truncating -- correct against production Canvas (always TLS,
            // F2/live1-report.md), but this dev stack's own `Link` header comes back `http://`
            // (same deviation F2/F3 already cover on the request side: Rails emits whatever
            // scheme/port it was actually reached on, and this harness reaches it over plain
            // HTTP). Left alone, every paginated endpoint here would now throw `.unknown` on its
            // second page -- reproduced once, confirmed read-only: `GET
            // /api/v1/planner/items?per_page=100` for the seeded student returns a `rel="next"`
            // link whose scheme is http even at that page size. Rewriting it back to https (and
            // dropping the forced port, restoring the bare host `CanvasClient`'s own
            // `allowedHosts` expects) here mirrors what production Canvas's own Link header
            // would actually look like, the same disclosed-deviation shape as `forceScheme`/
            // `forcePort` above -- never a change to `PageURLPolicy` or `CanvasClient` itself.
            if let link = headers["Link"] { headers["Link"] = Self.rewriteLinkHeaderToHTTPS(link) }
            return HTTPResponse(status: http.statusCode, headers: headers, body: data)
        } catch let error as TransportError {
            throw error
        } catch {
            throw Self.classify(error)
        }
    }

    /// Rewrites every `<url>` segment of a `Link` header to https, with no port -- the shape
    /// `PageURLPolicy.validate` requires and the one a real, TLS-only Canvas would actually send.
    static func rewriteLinkHeaderToHTTPS(_ header: String) -> String {
        var result = "", rest = Substring(header)
        while let open = rest.firstIndex(of: "<"), let close = rest[open...].firstIndex(of: ">") {
            result += rest[rest.startIndex..<open]
            let raw = String(rest[rest.index(after: open)..<close])
            if var components = URLComponents(string: raw) {
                components.scheme = "https"
                components.port = nil
                result += "<\(components.string ?? raw)>"
            } else {
                result += "<\(raw)>"
            }
            rest = rest[rest.index(after: close)...]
        }
        result += rest
        return result
    }

    private func send(_ urlRequest: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: urlRequest) { data, response, error in
                if let error { continuation.resume(throwing: error); return }
                guard let data, let response else { continuation.resume(throwing: TransportError.other); return }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }

    private static func urlRequest(for request: HTTPRequest, forceScheme: String, forcePort: Int?) -> URLRequest {
        var url = request.url
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = forceScheme
            components.port = forcePort
            url = components.url ?? url
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        // Item 3 (LIVE-FIX-2/LIVE-3): `If-None-Match`, the same addition the shipping
        // `URLSessionTransport`'s own `knownRequestHeaderNames` needed -- missing here first
        // produced a real, reproducible symptom: a second live refresh never got a single 304.
        for name in ["Accept", "User-Agent", "Content-Type", "Authorization", "If-None-Match"] {
            if let value = request.headers[name] { urlRequest.setValue(value, forHTTPHeaderField: name) }
        }
        return urlRequest
    }

    private static func headers(from http: HTTPURLResponse) -> HTTPHeaders {
        var pairs: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            guard let name = key as? String else { continue }
            pairs[name] = "\(value)"
        }
        return HTTPHeaders(pairs)
    }

    private static func classify(_ error: any Error) -> TransportError {
        guard let urlError = error as? URLError else { return .other }
        switch urlError.code {
        case .cancelled: return .cancelled
        case .timedOut: return .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return .offline
        default: return .other
        }
    }
}

/// Counts requests and response bytes around any wrapped transport, for the LIVE-PERF line
/// (brief assertion 5). Adds no behavior of its own -- every request still goes to `wrapped`
/// unchanged -- so it never affects what `CanvasClient` sees.
public actor MeteringTransport: HTTPTransport {
    private let wrapped: any HTTPTransport
    public private(set) var requestCount = 0
    public private(set) var byteCount = 0

    public init(wrapping transport: any HTTPTransport) { wrapped = transport }

    public func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
        let response = try await wrapped.send(request)
        requestCount += 1
        byteCount += response.body.count
        return response
    }
}

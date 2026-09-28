import Foundation
import TallyCanvasAPI

/// One route entry as `fixtures/canvas/manifest.json` records it (README "Using the
/// route table"): method + host + path + normalized query -> a recorded body and headers.
public struct RouteFixture: Decodable, Sendable, Equatable {
    public let endpoint: String
    public let method: String
    public let host: String
    public let path: String
    /// Percent-decoded, sorted `k=v&k=v`, exactly as the fixture was captured.
    public let query: String
    /// The same, with `start_date`/`end_date` values replaced by `*` so a rebased
    /// (demo-mode) request still matches.
    public let queryMatch: String
    public let status: Int
    /// Path to the body file, relative to `fixtures/canvas`.
    public let body: String
    /// Path to the `.headers.json` sidecar, relative to `fixtures/canvas`.
    public let headers: String
}

/// Percent-decode, sort by (key, value), join with `&` (manifest.json README
/// "Using the route table"). `wildcardDates` additionally blanks `start_date`/`end_date`
/// values to match a route's `query_match`.
enum QueryNormalizer {
    static func normalize(_ url: URL, wildcardDates: Bool = false) -> String {
        guard let query = url.query, !query.isEmpty else { return "" }
        let pairs = query.split(separator: "&").map { pair -> (String, String) in
            let parts = pair.split(separator: "=", maxSplits: 1)
            let key = decode(String(parts[0]))
            let value = parts.count > 1 ? decode(String(parts[1])) : ""
            return (key, (wildcardDates && (key == "start_date" || key == "end_date")) ? "*" : value)
        }
        return pairs.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
            .map { "\($0.0)=\($0.1)" }.joined(separator: "&")
    }

    private static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? s
    }
}

/// Replays fixture files as an `HTTPTransport` (architecture §3.3, §3.6): Linux tests, and the
/// app's sample mode (ASC-14) over its bundled persona. Loads a fixed route table up front (one
/// persona, one sub-account, or one scenario), then serves each request by method + host + path
/// + normalized query, from files under `root`. Unknown routes get `errors/404-not-found`. Tests
/// can also inject one-shot latency and/or an error response for requests matching a predicate
/// (401 with/without `WWW-Authenticate`, 429, 403 rate-limited, 5xx, or any other canned or ad hoc
/// response).
///
/// Plan 06 A1: this module ships in the app, so it holds no fixture *loader*: `root` is always
/// given (the app resolves its bundled copy), and nothing here can trap. `TallyTestSupport`
/// re-exports it and adds the source-tree factories (`persona(_:)` and the rest).
public actor ReplayTransport: HTTPTransport {
    private struct Injection {
        let predicate: @Sendable (HTTPRequest) -> Bool
        var remaining: Int
        let response: HTTPResponse?
        let latency: Duration?
    }

    private let routes: [RouteFixture]
    private let root: URL
    private var injections: [Injection] = []
    private var sentRequests: [HTTPRequest] = []

    public init(routes: [RouteFixture], root: URL) {
        self.routes = routes
        self.root = root
    }

    /// One of the canned bodies in `<root>/errors/<name>.json|.txt` plus its `.headers.json`
    /// sidecar (401 with/without `WWW-Authenticate`, 429, both 403 shapes, 5xx).
    public static func errorResponse(_ name: String, root: URL) throws -> HTTPResponse {
        let base = root.appendingPathComponent("errors/\(name)")
        let bodyPath = FileManager.default.fileExists(atPath: base.appendingPathExtension("json").path)
            ? "errors/\(name).json" : "errors/\(name).txt"
        return try loadFixture(body: bodyPath, headers: "errors/\(name).headers.json", root: root)
    }

    /// Requests seen so far, in order (e.g. to assert a request-count budget).
    public func requests() -> [HTTPRequest] { sentRequests }
    public var requestCount: Int { sentRequests.count }

    /// Serves `response` (or, with `response: nil`, only the delay) for the next `times`
    /// requests matching `predicate`, ahead of the normal fixture lookup.
    public func inject(response: HTTPResponse? = nil, latency: Duration? = nil, times: Int = 1,
                       matching predicate: @escaping @Sendable (HTTPRequest) -> Bool) {
        injections.append(Injection(predicate: predicate, remaining: times, response: response, latency: latency))
    }

    public func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
        sentRequests.append(request)
        if let index = injections.firstIndex(where: { $0.remaining > 0 && $0.predicate(request) }) {
            let latency = injections[index].latency
            let canned = injections[index].response
            injections[index].remaining -= 1
            if injections[index].remaining == 0 { injections.remove(at: index) }
            if let latency {
                do { try await Task.sleep(for: latency) } catch { throw .cancelled }
            }
            if let canned { return canned }
        }
        return lookUp(request)
    }

    private func lookUp(_ request: HTTPRequest) -> HTTPResponse {
        let host = request.url.host?.lowercased()
        let path = request.url.path
        let exactQuery = QueryNormalizer.normalize(request.url)
        let wildcardQuery = QueryNormalizer.normalize(request.url, wildcardDates: true)
        let match = routes.first {
            $0.method == request.method.rawValue && $0.host.lowercased() == host && $0.path == path
                && ($0.query == exactQuery || $0.queryMatch == wildcardQuery)
        }
        guard let match else { return (try? Self.errorResponse("404-not-found", root: root)) ?? HTTPResponse(status: 404) }
        return (try? Self.loadFixture(body: match.body, headers: match.headers, root: root))
            ?? HTTPResponse(status: match.status)
    }

    private static func loadFixture(body: String, headers headersPath: String, root: URL) throws -> HTTPResponse {
        let bodyData = try Data(contentsOf: root.appendingPathComponent(body))
        let headersData = try Data(contentsOf: root.appendingPathComponent(headersPath))
        struct Sidecar: Decodable { let status: Int; let headers: [String: String] }
        let sidecar = try JSONDecoder().decode(Sidecar.self, from: headersData)
        return HTTPResponse(status: sidecar.status, headers: HTTPHeaders(sidecar.headers), body: bodyData)
    }
}

import Foundation
import TallyCanvasAPI

/// `HTTPTransport` over `URLSession` (security.md §3.2 item 4 / SEC-08).
/// Ephemeral configuration — no on-disk `URLCache`, no cookie jar — so a
/// Canvas response can never persist outside the sealed vault
/// (encryption.md ENC-07). A per-request redirect delegate strips
/// `Authorization` the instant a redirect changes host, so a bearer token
/// can never follow Canvas onto a CDN or attachment host.
///
/// `HTTPHeaders` (`TallyCanvasAPI`, read-only from this package) exposes no
/// enumeration API — only case-insensitive get/set by name. Outbound headers
/// are therefore copied from a fixed, known set: every header name
/// `TallyCanvasAPI` is seen setting on a request today (`CanvasClient`,
/// `TokenEndpoint`). Extend `knownRequestHeaderNames` if a future TallyCore
/// change adds a new outbound request header — flagged for the PMO in the
/// platform-adapters report.
public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private static let knownRequestHeaderNames = ["Accept", "User-Agent", "Content-Type", "Authorization"]

    /// Internal (not private) so hosted tests can assert on the live
    /// configuration (`@testable import TallyPlatform`) without a second,
    /// parallel construction path.
    let session: URLSession

    /// `protocolClasses` lets hosted tests register a `URLProtocol` stub
    /// ahead of Foundation's defaults, without touching production
    /// configuration otherwise.
    public init(protocolClasses: [AnyClass]? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses + (configuration.protocolClasses ?? [])
        }
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
        let urlRequest = Self.urlRequest(for: request)
        let delegate = RedirectAuthorizationStrippingDelegate()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest, delegate: delegate)
        } catch {
            throw Self.classify(error)
        }
        guard let http = response as? HTTPURLResponse else { throw .other }
        return HTTPResponse(status: http.statusCode, headers: Self.responseHeaders(from: http), body: data)
    }

    /// Free function-shaped for direct unit testing (`URLSessionTransport.classify(_:)`),
    /// so the mapping table can be verified without a network round trip.
    static func classify(_ error: any Error) -> TransportError {
        guard let urlError = error as? URLError else { return .other }
        switch urlError.code {
        case .cancelled:
            return .cancelled
        case .timedOut:
            return .timedOut
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff:
            return .offline
        default:
            return .other
        }
    }

    private static func urlRequest(for request: HTTPRequest) -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for name in knownRequestHeaderNames {
            if let value = request.headers[name] {
                urlRequest.setValue(value, forHTTPHeaderField: name)
            }
        }
        return urlRequest
    }

    private static func responseHeaders(from http: HTTPURLResponse) -> HTTPHeaders {
        var pairs: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            guard let name = key as? String else { continue }
            pairs[name] = "\(value)"
        }
        return HTTPHeaders(pairs)
    }
}

/// Strips `Authorization` the instant a redirect crosses hosts (security.md
/// §3.2 item 4: "Redirect delegate strips Authorization when the host
/// changes"). One instance per request: `URLSessionTaskDelegate` hands the
/// task's own `originalRequest`, so no shared or racy state is needed across
/// concurrent requests sharing one `URLSession`.
final class RedirectAuthorizationStrippingDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var redirected = newRequest
        let originalHost = task.originalRequest?.url?.host?.lowercased()
        let newHost = newRequest.url?.host?.lowercased()
        if originalHost == newHost {
            redirected.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(redirected)
    }
}

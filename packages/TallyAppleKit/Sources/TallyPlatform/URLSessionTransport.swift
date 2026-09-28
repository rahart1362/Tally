import Foundation
import Synchronization
import TallyCanvasAPI
import TallyDomain

/// `HTTPTransport` over `URLSession` (security.md §3.2 item 4 / SEC-08).
/// Ephemeral configuration — no on-disk `URLCache`, no cookie jar — so a
/// Canvas response can never persist outside the sealed vault
/// (encryption.md ENC-07). Each request has its own task delegate
/// (`TransportTaskDelegate`), which strips `Authorization` the instant a
/// redirect changes host, so a bearer token can never follow Canvas onto a
/// CDN or attachment host, and enforces the response-size cap while the body
/// arrives (plan 06 A5), so an oversized response never sits in memory.
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
    /// The largest body accepted (CS-05's `TallyConfig.maxResponseBodyBytes`; tests use less).
    let maxBodyBytes: Int

    /// `protocolClasses` lets hosted tests register a `URLProtocol` stub
    /// ahead of Foundation's defaults, without touching production
    /// configuration otherwise.
    public convenience init(protocolClasses: [AnyClass]? = nil) {
        self.init(protocolClasses: protocolClasses, maxBodyBytes: TallyConfig.maxResponseBodyBytes)
    }

    init(protocolClasses: [AnyClass]?, maxBodyBytes: Int) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses + (configuration.protocolClasses ?? [])
        }
        session = URLSession(configuration: configuration)
        self.maxBodyBytes = maxBodyBytes
    }

    /// A response whose `Content-Length` is over the cap is cancelled as soon as its headers
    /// arrive; one without a length (chunked) is cancelled as soon as the bytes received pass
    /// it. Both throw `TransportError.other` (CS-05's contract) and hand nothing to a mapper.
    /// Cancelling the calling task cancels the request.
    public func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
        let task = session.dataTask(with: Self.urlRequest(for: request))
        let delegate = TransportTaskDelegate(maxBodyBytes: maxBodyBytes)
        task.delegate = delegate
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HTTPResponse, any Error>) in
                    delegate.install(continuation)
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
        } catch let error as TransportError {
            throw error
        } catch {
            throw Self.classify(error)
        }
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

    fileprivate static func responseHeaders(from http: HTTPURLResponse) -> HTTPHeaders {
        var pairs: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            guard let name = key as? String else { continue }
            pairs[name] = "\(value)"
        }
        return HTTPHeaders(pairs)
    }
}

/// One request's task delegate (`URLSessionTask.delegate`; URLSession keeps it until the task
/// completes). It does two jobs:
/// - strips `Authorization` the instant a redirect crosses hosts (security.md §3.2 item 4:
///   "Redirect delegate strips Authorization when the host changes"); it reads the task's own
///   `originalRequest`, so concurrent requests share nothing;
/// - enforces the response-size cap as the body arrives (plan 06 A5): CS-05 checked `data.count`
///   only after `URLSession.data(for:)` had buffered the whole body, which protected the mappers
///   but not memory. Here an over-cap `Content-Length` cancels the task at the headers, and a body
///   without one is cancelled, and what arrived released, once its running count passes the cap.
final class TransportTaskDelegate: NSObject, URLSessionDataDelegate, Sendable {
    private struct State {
        var continuation: CheckedContinuation<HTTPResponse, any Error>?
        var head: (status: Int, headers: HTTPHeaders)?
        var body = Data()
        /// Set when the response is refused (not HTTP, or over the cap): the task's own completion
        /// error (`cancelled`) is then reported as this.
        var refusal: TransportError?
    }

    private let maxBodyBytes: Int
    private let state = Mutex(State())

    init(maxBodyBytes: Int) {
        self.maxBodyBytes = maxBodyBytes
    }

    /// Called once, before the task resumes, so every later callback finds the continuation.
    func install(_ continuation: CheckedContinuation<HTTPResponse, any Error>) {
        state.withLock { $0.continuation = continuation }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse, response.expectedContentLength <= Int64(maxBodyBytes) else {
            state.withLock { $0.refusal = .other }
            completionHandler(.cancel)
            return
        }
        let head = (status: http.statusCode, headers: URLSessionTransport.responseHeaders(from: http))
        state.withLock { $0.head = head }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let overCap = state.withLock { state -> Bool in
            guard state.refusal == nil else { return false }
            state.body.append(data)
            guard state.body.count > maxBodyBytes else { return false }
            state.refusal = .other
            state.body = Data()
            return true
        }
        if overCap { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (continuation, result) = state.withLock { state -> (CheckedContinuation<HTTPResponse, any Error>?, Result<HTTPResponse, any Error>) in
            let continuation = state.continuation
            state.continuation = nil
            let body = state.body
            state.body = Data()
            if let refusal = state.refusal { return (continuation, .failure(refusal)) }
            if let error { return (continuation, .failure(error)) }
            guard let head = state.head else { return (continuation, .failure(TransportError.other)) }
            return (continuation, .success(HTTPResponse(status: head.status, headers: head.headers, body: body)))
        }
        continuation?.resume(with: result)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(Self.redirected(newRequest, from: task))
    }

    /// `newRequest` without `Authorization` when it leaves the task's original host.
    static func redirected(_ newRequest: URLRequest, from task: URLSessionTask) -> URLRequest {
        var redirected = newRequest
        let originalHost = task.originalRequest?.url?.host?.lowercased()
        let newHost = newRequest.url?.host?.lowercased()
        if originalHost != newHost {
            redirected.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        return redirected
    }
}

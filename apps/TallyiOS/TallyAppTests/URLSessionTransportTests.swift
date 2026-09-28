import Foundation
import Testing
import TallyCanvasAPI
@testable import TallyPlatform

/// SEC-08 / E03a. `.serialized`: every test in this suite drives the shared
/// `StubURLProtocol.rule` closure, so two tests must never run concurrently.
@Suite("URLSessionTransport", .serialized)
struct URLSessionTransportTests {
    @Test("ephemeral configuration: no on-disk cache, no cookie jar")
    func ephemeralConfiguration() {
        let transport = URLSessionTransport()
        let configuration = transport.session.configuration
        #expect(configuration.urlCache == nil)
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
    }

    @Test("a successful response round-trips status, headers and body")
    func successfulRequest() async throws {
        StubURLProtocol.rule = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-a")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["X-Rate-Limit-Remaining": "699.5"])!
            return .respond(response, Data(#"{"ok":true}"#.utf8))
        }
        let transport = URLSessionTransport(protocolClasses: [StubURLProtocol.self])
        var headers = HTTPHeaders()
        headers["Authorization"] = "Bearer token-a"
        let request = HTTPRequest(url: URL(string: "https://canvas.example.edu/api/v1/users/self/profile")!, headers: headers)

        let response = try await transport.send(request)

        #expect(response.status == 200)
        #expect(response.headers["X-Rate-Limit-Remaining"] == "699.5")
        #expect(response.body == Data(#"{"ok":true}"#.utf8))
    }

    @Test("URLError.notConnectedToInternet maps to .offline")
    func offlineMapping() async {
        StubURLProtocol.rule = { _ in .fail(URLError(.notConnectedToInternet)) }
        let transport = URLSessionTransport(protocolClasses: [StubURLProtocol.self])
        await #expect(throws: TransportError.offline) {
            _ = try await transport.send(HTTPRequest(url: URL(string: "https://canvas.example.edu/x")!))
        }
    }

    @Test("URLError.timedOut maps to .timedOut")
    func timedOutMapping() async {
        StubURLProtocol.rule = { _ in .fail(URLError(.timedOut)) }
        let transport = URLSessionTransport(protocolClasses: [StubURLProtocol.self])
        await #expect(throws: TransportError.timedOut) {
            _ = try await transport.send(HTTPRequest(url: URL(string: "https://canvas.example.edu/x")!))
        }
    }

    @Test("URLError.cancelled maps to .cancelled")
    func cancelledMapping() async {
        StubURLProtocol.rule = { _ in .fail(URLError(.cancelled)) }
        let transport = URLSessionTransport(protocolClasses: [StubURLProtocol.self])
        await #expect(throws: TransportError.cancelled) {
            _ = try await transport.send(HTTPRequest(url: URL(string: "https://canvas.example.edu/x")!))
        }
    }

    @Test("an unrecognised URLError maps to .other")
    func otherMapping() async {
        StubURLProtocol.rule = { _ in .fail(URLError(.badServerResponse)) }
        let transport = URLSessionTransport(protocolClasses: [StubURLProtocol.self])
        await #expect(throws: TransportError.other) {
            _ = try await transport.send(HTTPRequest(url: URL(string: "https://canvas.example.edu/x")!))
        }
    }

    @Test("classify() truth table (mutation-guarded: covers every mapped URLError code)")
    func classifyTruthTable() {
        #expect(URLSessionTransport.classify(URLError(.notConnectedToInternet)) == .offline)
        #expect(URLSessionTransport.classify(URLError(.networkConnectionLost)) == .offline)
        #expect(URLSessionTransport.classify(URLError(.cannotFindHost)) == .offline)
        #expect(URLSessionTransport.classify(URLError(.timedOut)) == .timedOut)
        #expect(URLSessionTransport.classify(URLError(.cancelled)) == .cancelled)
        #expect(URLSessionTransport.classify(URLError(.badURL)) == .other)
        #expect(URLSessionTransport.classify(CancellationError()) == .other)
    }
}

/// Redirect stripping is tested directly against the delegate: a real (never
/// `.resume()`d) `URLSessionTask` gives a real `originalRequest`, so this
/// covers the rule deterministically without a live redirect round trip
/// through the URL Loading System.
@Suite("RedirectAuthorizationStrippingDelegate")
struct RedirectAuthorizationStrippingDelegateTests {
    @Test("strips Authorization when the redirect target is a different host")
    func stripsCrossHost() {
        let session = URLSession(configuration: .ephemeral)
        var original = URLRequest(url: URL(string: "https://canvas.example.edu/a")!)
        original.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let task = session.dataTask(with: original)
        var redirectTarget = URLRequest(url: URL(string: "https://attachments.example.com/a")!)
        redirectTarget.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let redirectResponse = HTTPURLResponse(url: original.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!

        let delegate = RedirectAuthorizationStrippingDelegate()
        var captured: URLRequest?
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: redirectResponse, newRequest: redirectTarget) {
            captured = $0
        }

        #expect(captured?.value(forHTTPHeaderField: "Authorization") == nil)
        task.cancel()
    }

    @Test("keeps Authorization when the redirect stays on the same host")
    func keepsSameHost() {
        let session = URLSession(configuration: .ephemeral)
        var original = URLRequest(url: URL(string: "https://canvas.example.edu/a")!)
        original.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let task = session.dataTask(with: original)
        var redirectTarget = URLRequest(url: URL(string: "https://canvas.example.edu/b")!)
        redirectTarget.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let redirectResponse = HTTPURLResponse(url: original.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!

        let delegate = RedirectAuthorizationStrippingDelegate()
        var captured: URLRequest?
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: redirectResponse, newRequest: redirectTarget) {
            captured = $0
        }

        #expect(captured?.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        task.cancel()
    }
}

/// A minimal `URLProtocol` stub (implementation brief: "Tests with a
/// URLProtocol stub", WP SEC-08). `rule` is set by each test immediately
/// before use; the enclosing suite is `.serialized` so this is never raced.
enum StubHTTPResult {
    case respond(HTTPURLResponse, Data)
    case fail(URLError)
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var rule: ((URLRequest) -> StubHTTPResult)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let rule = Self.rule else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        switch rule(request) {
        case .respond(let response, let data):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .fail(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

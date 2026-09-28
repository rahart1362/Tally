import Foundation
import Synchronization
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

    // MARK: - Response-size cap while the body arrives (plan 06 A5)

    private static let cap = 1_000
    private static let url = URL(string: "https://canvas.example.edu/api/v1/courses")!

    @Test("a body of exactly the cap is accepted")
    func bodyAtTheCapIsAccepted() async throws {
        ChunkedStubURLProtocol.configure(contentLength: Self.cap, chunkSize: 250, chunks: 4)
        let transport = URLSessionTransport(protocolClasses: [ChunkedStubURLProtocol.self], maxBodyBytes: Self.cap)
        let response = try await transport.send(HTTPRequest(url: Self.url))
        #expect(response.status == 200)
        #expect(response.body.count == Self.cap)
    }

    @Test("Content-Length of cap + 1 is refused at the headers: TransportError.other, no body delivered")
    func overCapContentLengthIsRefusedAtTheHeaders() async {
        ChunkedStubURLProtocol.configure(contentLength: Self.cap + 1, chunkSize: 1, chunks: Self.cap + 1,
                                         firstChunkDelay: .milliseconds(500))
        let transport = URLSessionTransport(protocolClasses: [ChunkedStubURLProtocol.self], maxBodyBytes: Self.cap)
        await #expect(throws: TransportError.other) {
            _ = try await transport.send(HTTPRequest(url: Self.url))
        }
        #expect(ChunkedStubURLProtocol.deliveredChunks == 0, "the body was loaded although its length was over the cap")
    }

    @Test("a body without a length is cancelled once it passes the cap: TransportError.other")
    func chunkedOverCapBodyIsCancelledMidStream() async {
        // 40 chunks of 100 bytes = 4,000 bytes, 10 ms apart; the cap is passed at chunk 11.
        ChunkedStubURLProtocol.configure(contentLength: nil, chunkSize: 100, chunks: 40)
        let transport = URLSessionTransport(protocolClasses: [ChunkedStubURLProtocol.self], maxBodyBytes: Self.cap)
        await #expect(throws: TransportError.other) {
            _ = try await transport.send(HTTPRequest(url: Self.url))
        }
        // URLSession calls `stopLoading` on the stub's own thread after it cancels the task, which
        // can be after `send` has thrown (ios-tsan, run 36390172728): wait up to 2 s for it.
        let deadline = ContinuousClock.now + .seconds(2)
        while !ChunkedStubURLProtocol.wasStopped, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(ChunkedStubURLProtocol.wasStopped, "the request was not cancelled")
        #expect(ChunkedStubURLProtocol.deliveredChunks < 40, "every chunk was loaded: the cap did not stop the stream")
    }

    /// Plan 06 A5's budget: the cap's cost on a 300 KB page is under 5 ms (medians of 15 loads,
    /// against `URLSession.data(for:)` over the same stub).
    @Test("the cap costs under 5 ms on a 300 KB page")
    func capOverheadOn300KB() async throws {
        let size = 300 * 1_024
        ChunkedStubURLProtocol.configure(contentLength: size, chunkSize: 16 * 1_024, chunks: size / (16 * 1_024) + 1,
                                         lastChunkSize: size % (16 * 1_024), interChunkDelay: .zero)
        let transport = URLSessionTransport(protocolClasses: [ChunkedStubURLProtocol.self])
        let clock = ContinuousClock()
        var capped: [Duration] = []
        var plain: [Duration] = []
        for _ in 0..<15 {
            ChunkedStubURLProtocol.reset()
            capped.append(try await clock.measure { _ = try await transport.send(HTTPRequest(url: Self.url)) })
            ChunkedStubURLProtocol.reset()
            plain.append(try await clock.measure { _ = try await transport.session.data(from: Self.url) })
        }
        let overhead = capped.sorted()[7] - plain.sorted()[7]
        #expect(overhead < .milliseconds(5), "median overhead \(overhead) (capped \(capped.sorted()[7]), plain \(plain.sorted()[7]))")
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

/// Redirect stripping is tested directly against the transport's task delegate: a real (never
/// `.resume()`d) `URLSessionTask` gives a real `originalRequest`, so this covers the rule
/// deterministically without a live redirect round trip through the URL Loading System.
@Suite("TransportTaskDelegate: redirects")
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

        let delegate = TransportTaskDelegate(maxBodyBytes: 1_000)
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

        let delegate = TransportTaskDelegate(maxBodyBytes: 1_000)
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

/// A `URLProtocol` stub that streams its body in chunks from a background queue, recording how
/// many chunks it delivered and whether the loading system stopped it (plan 06 A5's cap tests).
/// Used only by the `.serialized` `URLSessionTransport` suite.
final class ChunkedStubURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Config {
        var contentLength: Int?
        var chunkSize = 100
        var chunks = 1
        var lastChunkSize = 0
        var firstChunkDelay: Duration = .zero
        var interChunkDelay: Duration = .milliseconds(10)
    }

    private struct Progress {
        /// Bumped by `reset()`: a late `stopLoading` from an earlier load never counts.
        var generation = 0
        var delivered = 0
        var stopped = false
    }

    private static let config = Mutex(Config())
    private static let progress = Mutex(Progress())
    private let queue = DispatchQueue(label: "chunked-stub")
    /// This load's own flag, so one load's stop never silences the next.
    private let stopped = Mutex(false)
    private let generation = Mutex(0)

    static func configure(contentLength: Int?, chunkSize: Int, chunks: Int, lastChunkSize: Int = 0,
                          firstChunkDelay: Duration = .zero, interChunkDelay: Duration = .milliseconds(10)) {
        config.withLock {
            $0 = Config(contentLength: contentLength, chunkSize: chunkSize, chunks: chunks, lastChunkSize: lastChunkSize,
                        firstChunkDelay: firstChunkDelay, interChunkDelay: interChunkDelay)
        }
        reset()
    }

    static func reset() { progress.withLock { $0 = Progress(generation: $0.generation + 1) } }
    static var deliveredChunks: Int { progress.withLock { $0.delivered } }
    static var wasStopped: Bool { progress.withLock { $0.stopped } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let config = Self.config.withLock { $0 }
        var headers = ["Content-Type": "application/json"]
        if let length = config.contentLength { headers["Content-Length"] = String(length) }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        generation.withLock { $0 = Self.progress.withLock { $0.generation } }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        deliver(chunk: 0, config: config, after: config.firstChunkDelay)
    }

    private func deliver(chunk index: Int, config: Config, after delay: Duration) {
        let nanoseconds = Int(delay.components.seconds) * 1_000_000_000 + Int(delay.components.attoseconds / 1_000_000_000)
        queue.asyncAfter(deadline: .now() + .nanoseconds(nanoseconds)) { [self] in
            guard !stopped.withLock({ $0 }) else { return }
            guard index < config.chunks else {
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            let isLast = index == config.chunks - 1 && config.lastChunkSize > 0
            client?.urlProtocol(self, didLoad: Data(repeating: 0x20, count: isLast ? config.lastChunkSize : config.chunkSize))
            Self.progress.withLock { $0.delivered += 1 }
            deliver(chunk: index + 1, config: config, after: config.interChunkDelay)
        }
    }

    override func stopLoading() {
        stopped.withLock { $0 = true }
        let mine = generation.withLock { $0 }
        Self.progress.withLock { if $0.generation == mine { $0.stopped = true } }
    }
}

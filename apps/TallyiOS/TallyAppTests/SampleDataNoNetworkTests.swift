import Foundation
import Synchronization
import Testing
@testable import TallyFeatures

/// ASC-14: "No network calls in sample mode. Assert this with a test transport or URLProtocol
/// that fails on any real request." `SampleDataCanvasGateway` never uses `URLSession` at all (it
/// is built entirely on `TallyTestSupport.ReplayTransport` over bundled fixture files), so this
/// registers a `URLProtocol` that fails — and records — *any* request made through the default
/// `URLSessionConfiguration`, then drives the full sample-data fetch path end to end and asserts
/// it was never invoked. This is the belt-and-suspenders half of the guarantee: even if a future
/// change accidentally introduced a `URLSession` call anywhere on this path, this test would fail.
@Suite("Sample data: no network calls")
struct SampleDataNoNetworkTests {
    final class FailOnAnyRequestURLProtocol: URLProtocol, @unchecked Sendable {
        static let invocationCount = Mutex<Int>(0)

        override class func canInit(with request: URLRequest) -> Bool {
            invocationCount.withLock { $0 += 1 }
            return true
        }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let error = NSError(domain: "SampleDataNoNetworkTests", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Sample mode must never make a real network request"])
            client?.urlProtocol(self, didFailWithError: error)
        }
        override func stopLoading() {}
    }

    @Test("fetching a full sample-data snapshot never triggers any URLSession request")
    func noNetworkDuringSampleFetch() async throws {
        URLProtocol.registerClass(FailOnAnyRequestURLProtocol.self)
        defer { URLProtocol.unregisterClass(FailOnAnyRequestURLProtocol.self) }
        let before = FailOnAnyRequestURLProtocol.invocationCount.withLock { $0 }

        let gateway = try await SampleDataCanvasGateway.make()
        let snapshot = try await gateway.fetchSnapshot(previous: nil, now: Date())

        #expect(snapshot.courses.count == 5)
        #expect(FailOnAnyRequestURLProtocol.invocationCount.withLock { $0 } == before)
    }

    @Test("sample entry end to end (session, model, refresh) never triggers any URLSession request")
    @MainActor
    func noNetworkThroughSampleDataModel() async throws {
        URLProtocol.registerClass(FailOnAnyRequestURLProtocol.self)
        defer { URLProtocol.unregisterClass(FailOnAnyRequestURLProtocol.self) }
        let before = FailOnAnyRequestURLProtocol.invocationCount.withLock { $0 }

        let model = SampleDataModel()
        await model.start()
        await model.refresh()
        for _ in 0..<100 where model.snapshot == nil { try await Task.sleep(for: .milliseconds(10)) }

        #expect(model.snapshot?.courses.count == 5)
        #expect(FailOnAnyRequestURLProtocol.invocationCount.withLock { $0 } == before)
    }
}

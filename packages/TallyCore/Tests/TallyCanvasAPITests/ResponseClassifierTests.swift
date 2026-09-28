import Foundation
import Testing
import TallyDomain
@testable import TallyCanvasAPI

@Suite("Canvas response classification")
struct ResponseClassifierTests {
    private func r(_ status: Int, _ headers: [String: String] = [:], body: String = "") -> HTTPResponse {
        HTTPResponse(status: status, headers: HTTPHeaders(headers), body: Data(body.utf8))
    }

    @Test func tokenVersusScope401() {
        #expect(ResponseClassifier.classify(r(401, ["www-authenticate": #"Bearer realm="canvas-lms""#])) == .tokenRejected)
        #expect(ResponseClassifier.classify(r(401, body: #"{"errors":[{"message":"Insufficient scopes on access token."}]}"#)) == .insufficientScope)
    }

    @Test func bothRateLimitShapes() {
        #expect(ResponseClassifier.classify(r(429)) == .rateLimited)
        #expect(ResponseClassifier.classify(r(403, body: "403 Forbidden (Rate Limit Exceeded)")) == .rateLimited)
        #expect(ResponseClassifier.classify(r(403, body: #"{"status":"unauthorized"}"#)) == .forbidden)
    }

    @Test(arguments: [(200, ResponseClass.success), (204, .success), (404, .notFound),
                      (500, .serverError), (503, .serverError), (302, .unexpected(status: 302))])
    func statusTable(_ status: Int, _ expected: ResponseClass) {
        #expect(ResponseClassifier.classify(r(status)) == expected)
    }

    @Test func mapsToRefreshFailures() {
        #expect(ResponseClassifier.refreshFailure(for: .tokenRejected) == .authExpired)
        #expect(ResponseClassifier.refreshFailure(for: .rateLimited) == .rateLimited)
        #expect(ResponseClassifier.refreshFailure(for: .serverError) == .server)
        #expect(ResponseClassifier.refreshFailure(for: .success) == nil)
    }

    @Test func rateLimitHeaders() {
        let info = RateLimitInfo(r(200, ["x-rate-limit-remaining": "42.5", "X-Request-Cost": " 1.25 "]))
        #expect(info.remaining == 42.5 && info.cost == 1.25)
        #expect(info.isLow(threshold: 100))
        #expect(!RateLimitInfo(r(200)).isLow())
    }
}

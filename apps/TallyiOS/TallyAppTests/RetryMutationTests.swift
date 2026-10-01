import Foundation
import XCTest

/// TEMPORARY mutation check for `IOS_RETRY` (removed before merge): fails its first attempt and
/// passes its retry, so a green `ios-test` run with a "Failed attempt" warning proves the retry works.
final class RetryMutationTests: XCTestCase {
    func testFailsOnceThenPassesOnRetry() throws {
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("tally-retry-mutation")
        if FileManager.default.fileExists(atPath: marker.path) {
            try? FileManager.default.removeItem(at: marker)
            return
        }
        try Data().write(to: marker)
        XCTFail("first attempt fails on purpose (retry mutation check)")
    }
}

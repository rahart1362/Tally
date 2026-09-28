import XCTest

/// The base class for every Tally UI test (perf-app-runtime.md §7 step 3).
///
/// - `launchApp(arguments:)` is the one way a test starts the app, so launch configuration lives
///   in one place.
/// - `tapWhenHittable(_:)` taps a control only once it is actually hittable. A control that exists
///   but is covered or off screen fails the test at the call site, with the hierarchy, instead of
///   XCUITest tapping whatever lies on top of it.
class TallyUITestCase: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    @discardableResult
    func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += arguments
        app.launch()
        return app
    }

    /// Waits up to `timeout` for `element` to exist and become hittable, asserts it did, then taps.
    @MainActor
    func tapWhenHittable(
        _ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 10,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "\(element) never appeared. Hierarchy: \(app.debugDescription)", file: file, line: line)
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: timeout), .completed,
                       "\(element) exists but is not hittable. Hierarchy: \(app.debugDescription)",
                       file: file, line: line)
        element.tap()
    }
}

import Foundation
import Testing
@testable import TallyFeatures

/// Idea 9 (ideas1 report, "Handoff to Mac/iPad browser from an assignment"): the pure URL rule and
/// the `NSUserActivity` it configures. Invalidation itself is `.userActivity(_:element:_:)`
/// retiring a previously published activity once `webpageURL` returns `nil` (and, on sign-out, the
/// signed-in route's views going away entirely) — not something this process can observe directly,
/// so these tests pin the one thing it is driven by: `webpageURL` returning `nil` exactly when
/// Handoff must not be offered or must stop being offered.
@Suite("Idea 9: Handoff to Mac/iPad browser")
struct CanvasHandoffActivityTests {
    @Test("SEC1-15: an https URL on the account's own host, not sample data, is offered for Handoff")
    func offeredOnOwnHost() throws {
        let web = try #require(URL(string: "https://canvas.northfield.example/courses/51842/assignments/1204405"))
        #expect(CanvasHandoffActivity.webpageURL(for: web, accountHost: "canvas.northfield.example", isSampleData: false) == web)
    }

    @Test("ASC-14: sample data is never offered for Handoff, even on what would otherwise be a safe host")
    func neverOfferedForSampleData() throws {
        let web = try #require(URL(string: "https://canvas.northfield.example/courses/51842/assignments/1204405"))
        #expect(CanvasHandoffActivity.webpageURL(for: web, accountHost: "canvas.northfield.example", isSampleData: true) == nil)
    }

    @Test("no assignment open yet (no canvas URL): nothing is offered")
    func noURLYet() {
        #expect(CanvasHandoffActivity.webpageURL(for: nil, accountHost: "canvas.northfield.example", isSampleData: false) == nil)
    }

    @Test("SEC1-15: anything CanvasLinkOpener.isSafe would reject is never offered for Handoff", arguments: [
        "https://canvas-login.example/phish", // a different host entirely
        "http://canvas.northfield.example/courses/1", // not https
        "https://attacker:pw@canvas.northfield.example/courses/1", // embedded credentials
        "https://canvas.northfield.example:8443/courses/1", // non-standard port
        "canvas-courses://canvas.northfield.example/courses/1", // not http(s)
    ])
    func rejectsEverythingIsSafeRejects(_ string: String) throws {
        let url = try #require(URL(string: string))
        #expect(CanvasHandoffActivity.webpageURL(for: url, accountHost: "canvas.northfield.example", isSampleData: false) == nil)
    }

    @Test("an empty account host (no one signed in) is never offered for Handoff")
    func failsClosedWithNoAccount() throws {
        let web = try #require(URL(string: "https://canvas.northfield.example/courses/1"))
        #expect(CanvasHandoffActivity.webpageURL(for: web, accountHost: "", isSampleData: false) == nil)
    }

    @Test("configure sets webpageURL and opts out of search and prediction")
    func configure() throws {
        let web = try #require(URL(string: "https://canvas.northfield.example/courses/51842/assignments/1204405"))
        let activity = NSUserActivity(activityType: CanvasHandoffActivity.activityType)
        CanvasHandoffActivity.configure(activity, webpageURL: web)
        #expect(activity.webpageURL == web)
        #expect(activity.isEligibleForSearch == false)
        #expect(activity.isEligibleForPrediction == false)
    }
}

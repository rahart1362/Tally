import Testing
@testable import TallyFeatures

/// Plan 06 A8 (crash-safety-2.md §8 A4/A5): the onboarding stack's "choose a different school" and
/// "retry" edits used `path.removeLast()`, which traps on an empty path. `WelcomePath` applies an
/// edit only while the page that asks for it is on top.
@Suite("WelcomePath: onboarding path edits never trap and never touch another page")
struct WelcomePathTests {
    private static let signIn = WelcomeRoute.signIn(host: "canvas.example.edu", clientID: "10000000000001",
                                                    schoolDisplayName: "Example University")
    private static let firstSync = WelcomeRoute.firstSync(schoolDisplayName: "Example University")

    @Test("pop on an empty path is a no-op (it used to trap)")
    func popOnAnEmptyPath() {
        var path: [WelcomeRoute] = []
        WelcomePath.pop(Self.signIn, from: &path)
        #expect(path.isEmpty)
    }

    @Test("pop removes the page that asked, when it is on top; a second tap during the pop does nothing")
    func popTheTopPageOnce() {
        var path: [WelcomeRoute] = [.findSchool, Self.signIn]
        WelcomePath.pop(Self.signIn, from: &path)
        #expect(path == [.findSchool])
        WelcomePath.pop(Self.signIn, from: &path) // the repeated tap
        #expect(path == [.findSchool])
    }

    @Test("a stale pop from a page no longer on top leaves the path alone")
    func stalePopIsIgnored() {
        var path: [WelcomeRoute] = [.findSchool, Self.signIn, Self.firstSync]
        WelcomePath.pop(Self.signIn, from: &path)
        #expect(path == [.findSchool, Self.signIn, Self.firstSync])
    }

    @Test("restart replaces the top page with itself; on an empty or stale path it does nothing")
    func restartOnlyTheTopPage() {
        var path: [WelcomeRoute] = [.findSchool, Self.signIn, Self.firstSync]
        WelcomePath.restart(Self.firstSync, in: &path)
        #expect(path == [.findSchool, Self.signIn, Self.firstSync])

        var empty: [WelcomeRoute] = []
        WelcomePath.restart(Self.firstSync, in: &empty) // it used to trap, then push
        #expect(empty.isEmpty)

        var stale: [WelcomeRoute] = [.findSchool]
        WelcomePath.restart(Self.firstSync, in: &stale)
        #expect(stale == [.findSchool])
    }
}

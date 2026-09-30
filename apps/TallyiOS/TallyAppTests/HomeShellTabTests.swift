#if DEBUG
import SwiftUI
import Testing
import UIKit
@testable import TallyFeatures

/// PERF-L (`Launch.HomeRender`): the Home shell builds the selected tab only. The real `RootView`
/// is hosted on the sample route in a window of the test host's scene, with the DEBUG
/// `BodyEvaluationCounter` in its environment: once the Dashboard has rendered its full projection,
/// the Dashboard tab's content has been evaluated and no other tab's has. Selecting a tab builds it
/// and a built tab keeps its state; `HomeShellTabsUITests` checks both through the tab bar.
@Suite("Home shell: only the selected tab is built", .serialized)
@MainActor
struct HomeShellTabTests {
    @Test("at launch only the Dashboard tab's content is built; the other four wait for their first selection")
    func onlyTheDashboardIsBuiltAtLaunch() async throws {
        let appModel = AppModel()
        appModel.bootstrap()
        appModel.enterSample()
        let home = try #require(appModel.home)
        let counter = BodyEvaluationCounter()
        let host = UIHostingController(rootView: RootView(appModel: appModel).environment(\.bodyEvaluationCounter, counter))
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        #expect(try await HomeTestSupport.waitUntil { home.phase == .loaded }, "the sample projection never landed")
        try await Task.sleep(for: .milliseconds(500)) // SwiftUI renders the loaded dashboard

        #expect(counter.count("HomeTab.dashboard") > 0, "the Dashboard tab was never built")
        #expect(counter.count("DashboardView") > 0, "the hosted dashboard never rendered")
        for tab in HomeTab.allCases where tab != .dashboard {
            #expect(counter.count("HomeTab.\(tab.rawValue)") == 0, "the unselected \(tab) tab was built at launch")
        }

        appModel.exitSample()
        await appModel.awaitTeardown()
    }
}
#endif

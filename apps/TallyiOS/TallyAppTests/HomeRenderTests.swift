#if DEBUG
import SwiftUI
import Testing
import TallyDomain
import UIKit
@testable import TallyFeatures

/// perf-app-runtime.md §7 step 6: "refreshing → fresh changes 0 `DashboardView` bodies". The real
/// `DashboardView` is hosted in a `UIHostingController` in a window of the test host's scene, with
/// the DEBUG `BodyEvaluationCounter` in its environment. A freshness-only update must re-render
/// the freshness leaves (the footer), and never the dashboard itself.
@Suite("Home rendering: freshness re-renders only its leaves", .serialized)
@MainActor
struct HomeRenderTests {
    @Test("refreshing → fresh re-evaluates the footer, and zero DashboardView bodies")
    func freshnessChangeDoesNotReRenderTheDashboard() async throws {
        let snapshot = try await FlagshipSnapshotHarness.fetchSnapshot(now: HomeTestSupport.anchor)
        let source = FakeHomeSource(HomeTestSupport.update(snapshot, generation: 1,
                                                           freshness: .refreshing(showing: HomeTestSupport.anchor)))
        let model = HomeModel(source: source)
        let counter = BodyEvaluationCounter()
        let host = UIHostingController(rootView:
            NavigationStack { DashboardView() }
                .environment(model)
                .environment(\.bodyEvaluationCounter, counter))
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        await model.start()
        #expect(try await HomeTestSupport.waitUntil { model.phase == .loaded })
        try await Task.sleep(for: .milliseconds(300)) // SwiftUI renders the loaded dashboard
        let dashboardBodies = counter.count("DashboardView")
        let footerBodies = counter.count("FreshnessFooter")
        #expect(dashboardBodies > 0 && footerBodies > 0, "the hosted dashboard never rendered")

        await source.send(HomeTestSupport.update(snapshot, generation: 1, freshness: .fresh(at: HomeTestSupport.anchor)))
        #expect(try await HomeTestSupport.waitUntil { model.freshness == .fresh(at: HomeTestSupport.anchor) })
        try await Task.sleep(for: .milliseconds(300))

        #expect(counter.count("FreshnessFooter") > footerBodies, "the freshness change never reached the footer")
        #expect(counter.count("DashboardView") == dashboardBodies,
                "a freshness-only change re-evaluated DashboardView's body")
    }
}
#endif

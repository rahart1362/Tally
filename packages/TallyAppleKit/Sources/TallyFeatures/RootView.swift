import SwiftUI
import TallyCanvasAPI
import TallyDesignSystem

/// The app's single root view (architecture.md §3.1: the `Tally` target is "composition root
/// only"; everything else, including navigation, lives here in `TallyFeatures`). It is one
/// `switch` over `AppModel.route` (perf-app-runtime.md §3 item 1):
///
/// - `.launching`: the launch colour, until `AppModel.bootstrap()` resolves the route.
/// - `.welcome`: `WelcomeFlowView`, onboarding's `NavigationStack` of plain pushed pages.
/// - `.sample` / `.signedIn`: `HomeShellView`, the root `TabView` whose tabs own their stacks.
///
/// **Navigation rule** (CONTRIBUTING.md code-review checklist): `TabView` and `NavigationStack`
/// appear only as a root, or as a tab's root inside the root `TabView` — never inside a pushed
/// destination. CI (runs 36348080137 → 36353526769, five configurations bisected one variable at a
/// time) proved a `TabView` pushed onto a `NavigationStack` never renders (the app simply stayed
/// on Welcome), while the same content as a root works (2d3131f, run 36354897417). This file is
/// the only shipping file allowed to construct the Home shell; CI's hygiene job enforces it.
public struct RootView: View {
    private let appModel: AppModel
    private let webAuthPresenter: any WebAuthPresenting
    private let tokenExchange: any TokenExchanging

    /// - Parameters:
    ///   - appModel: the composition root's one `AppModel` (it owns `route`).
    ///   - webAuthPresenter: injected by the composition root (architecture.md
    ///     §3.1: "the app's composition root injects adapters through
    ///     protocols") — `TallyFeatures` cannot construct `TallyPlatform`'s
    ///     `WebAuthPresenter` itself. Defaults to `UnavailableWebAuthPresenter`.
    ///   - tokenExchange: defaults to `UnavailableTokenExchange` until the
    ///     composition root can supply a real `HTTPTransport` (see
    ///     `CanvasAccountSearch`'s identical seam, UX-WP-08).
    public init(
        appModel: AppModel,
        webAuthPresenter: (any WebAuthPresenting)? = nil,
        tokenExchange: any TokenExchanging = UnavailableTokenExchange()
    ) {
        self.appModel = appModel
        self.webAuthPresenter = webAuthPresenter ?? UnavailableWebAuthPresenter()
        self.tokenExchange = tokenExchange
    }

    public var body: some View {
        switch appModel.route {
        case .launching:
            TallyColor.bgCanvas
                .ignoresSafeArea()
                .task { appModel.bootstrap() }
        case .welcome:
            WelcomeFlowView(
                playsBrandMoment: appModel.playsBrandMoment,
                webAuthPresenter: webAuthPresenter,
                tokenExchange: tokenExchange,
                onExploreSampleData: { appModel.enterSample() }
            )
        case .sample:
            if let sample = appModel.sample {
                SampleDataRootView(
                    model: sample,
                    onExit: { appModel.exitSample() },
                    onAppear: { await appModel.sampleDidAppear() }
                ) { model in
                    HomeShellView(
                        snapshot: model.snapshot, digest: model.digest, digestAsOf: model.digestAsOf,
                        freshness: model.freshness, studentDisplayName: model.studentDisplayName,
                        banner: AnyView(SampleDataBanner(onExit: { appModel.exitSample() })),
                        onRefresh: { await model.refresh() }
                    )
                }
            }
        case .signedIn:
            // No account session exists yet (perf-app-runtime.md §7 step 9), so every tab shows its
            // honest empty state; the refresh status is the one real, attached source.
            HomeShellView(
                snapshot: nil, digest: appModel.refreshStatus.lastDigest,
                digestAsOf: appModel.refreshStatus.lastDigestAt, freshness: appModel.refreshStatus.freshness,
                onRefresh: { await appModel.refreshStatus.refresh() }
            )
        }
    }
}

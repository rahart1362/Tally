import Synchronization
import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

/// perf-app-runtime.md §3 item 3: freshness is read only by these leaf views, so a change of
/// freshness (`.refreshing` → `.fresh`) re-renders a footer, a breadcrumb and a subtitle, never a
/// whole screen. Each takes the current time from a `TimelineView` context (not `Date()` in a
/// body), which also moves "Updated 2:14 PM" along once a minute.

/// The hero's "Updated …" line and its refresh button (UX-WP-06).
struct FreshnessFooter: View {
    @Environment(HomeModel.self) private var model
    #if DEBUG
    @Environment(\.bodyEvaluationCounter) private var bodyCounter
    #endif

    var body: some View {
        TimelineView(.everyMinute) { context in
            // Counted here, not in `body`: `model.freshness` is read in this closure, so a
            // freshness change re-evaluates the closure, not `FreshnessFooter.body`.
            #if DEBUG
            let _ = bodyCounter?.record("FreshnessFooter")
            #endif
            let presentation = FreshnessPresenter.present(model.freshness, now: context.date)
            HStack {
                Text(presentation.shortText)
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textOnHero2)
                Spacer()
                // Its own accessibility element (never combined into the hero): a control must
                // stay tappable for VoiceOver.
                Button {
                    model.requestRefresh()
                } label: {
                    // D08: the glyph had no explicit colour and inherited the system accent, 2.18:1
                    // on the navy hero — the same "dark glyph on navy" family as D06. The "Updated
                    // just now" text beside it already uses this token at 11.7:1.
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(TallyColor.textOnHero2)
                        .frame(width: 44, height: 44)
                }
                .disabled(presentation.action == .none)
                .accessibilityLabel(String(localized: L10n.Freshness.refreshButtonLabel()))
            }
        }
    }
}

/// UX-WP-06: the subtle stale breadcrumb (ux-ui.md §3.3), shown only when `FreshnessPresenter`
/// produces a `longText` (delayed/offline/failed/authExpired with saved data on screen).
struct FreshnessBreadcrumb: View {
    @Environment(HomeModel.self) private var model

    var body: some View {
        TimelineView(.everyMinute) { context in
            if let text = FreshnessPresenter.present(model.freshness, now: context.date).longText {
                Text(text)
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, TallySpacing.screenMargin)
                    .padding(.vertical, TallySpacing.sm)
                    // D21: a rounded warning-token card instead of a square-cornered, hard-coded
                    // `.orange` wash — every other surface on these screens is a rounded card.
                    .background(TallyColor.warning.opacity(0.16), in: RoundedRectangle(cornerRadius: TallyRadius.tile, style: .continuous))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }
}

/// The freshness subtitle under each non-Dashboard tab's title (replaces the shell's old
/// `freshnessSubtitle`, which ran on every shell body evaluation).
struct FreshnessSubtitle: ViewModifier {
    @Environment(HomeModel.self) private var model

    func body(content: Content) -> some View {
        TimelineView(.everyMinute) { context in
            content.navigationSubtitle(FreshnessPresenter.present(model.freshness, now: context.date).shortText)
        }
    }
}

#if DEBUG
/// DEBUG-only: counts body evaluations per view, for `HomeRenderTests` ("refreshing → fresh
/// re-evaluates zero `DashboardView` bodies"). Nil in the environment unless a test injects one.
nonisolated final class BodyEvaluationCounter: Sendable {
    private let counts = Mutex<[String: Int]>([:])

    func record(_ view: String) {
        counts.withLock { $0[view, default: 0] += 1 }
    }

    func count(_ view: String) -> Int {
        counts.withLock { $0[view, default: 0] }
    }
}

/// Spelled out rather than `@Entry`: this module defaults to `@MainActor`, and an environment
/// key's `defaultValue` must stay nonisolated.
nonisolated struct BodyEvaluationCounterKey: EnvironmentKey {
    static let defaultValue: BodyEvaluationCounter? = nil
}

extension EnvironmentValues {
    nonisolated var bodyEvaluationCounter: BodyEvaluationCounter? {
        get { self[BodyEvaluationCounterKey.self] }
        set { self[BodyEvaluationCounterKey.self] = newValue }
    }
}
#endif

import SwiftUI
import TallyDesignSystem

/// The launch colour (UX-WP-03: `bg.canvas`, the same values as the `LaunchBackground` colour set
/// the system's launch screen uses, so the first frame never flashes). It is the first frame of
/// every launch (perf-app-runtime.md §2.4 L2) and doubles as the **privacy cover** (ADR 0001 step
/// 1; ux-ui.md §3.7.8): opaque, never a material, so no grade can show through it in the app
/// switcher or before the lock decision.
struct LaunchPlaceholderView: View {
    enum Role {
        /// `RootRoute.launching`: the launch colour alone, exactly the system launch screen.
        case launch
        /// The privacy cover on `.inactive`: the launch colour plus a redacted hero silhouette
        /// (ux-ui.md §3.7.8), so the app switcher shows a recognisable, content-free Tally card.
        case privacyCover
    }

    var role: Role = .launch

    var body: some View {
        ZStack {
            TallyColor.bgCanvas
                .ignoresSafeArea()
            if role == .privacyCover {
                HeroSilhouette()
                    .padding(.horizontal, TallySpacing.screenMargin)
            }
        }
        .accessibilityElement(children: .ignore)
        // "Tally" is the brand name, never translated (plan 08 §3.7): verbatim, not a catalog key.
        .accessibilityLabel(role == .privacyCover ? Text(verbatim: "Tally") : Text(verbatim: ""))
        .accessibilityIdentifier(role == .privacyCover ? "privacy.cover" : "launch.placeholder")
    }
}

/// The hero card's shape with nothing in it: no figures, no names.
private struct HeroSilhouette: View {
    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: TallyRadius.hero, style: .continuous)
                .fill(TallyColor.bgBrand)
                .frame(height: 160)
                .overlay(alignment: .leading) {
                    TMark(size: 48)
                        .padding(TallySpacing.lg)
                }
            Spacer()
        }
        .padding(.top, TallySpacing.xxxl)
    }
}

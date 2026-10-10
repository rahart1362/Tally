import SwiftUI
import TallyDesignSystem

/// The launch colour (UX-WP-03: `bg.canvas`, the same values as the `LaunchBackground` colour set
/// the system's launch screen uses, so the first frame never flashes). It is the first frame of
/// every launch (perf-app-runtime.md §2.4 L2) and doubles as the **privacy cover** (ADR 0001 step
/// 1; ux-ui.md §3.7.8): opaque, never a material, so no grade can show through it in the app
/// switcher or before the lock decision.
///
/// ux-fp5 D24: the privacy cover used to be a small navy rounded rect (160 pt, with a 48 pt T-mark
/// pinned to its leading edge) floating near the top of an otherwise blank `bg.canvas` page — "a
/// navy block with a small icon on a blank page," read as a half-loaded screen in the app switcher.
/// It now fills the whole card with `bg.brand` and centres the T-mark on it, the same brand-panel
/// treatment `WelcomeView.brandPanel` uses, so the switcher shows a deliberate, recognisable,
/// content-free Tally card instead.
struct LaunchPlaceholderView: View {
    enum Role {
        /// `RootRoute.launching`: the launch colour alone, exactly the system launch screen.
        case launch
        /// The privacy cover on `.inactive`: the brand panel (ux-ui.md §3.7.8), so the app switcher
        /// shows a recognisable, content-free Tally card.
        case privacyCover
    }

    var role: Role = .launch

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()
            if role == .privacyCover {
                TMark(size: 96)
            }
        }
        .accessibilityElement(children: .ignore)
        // "Tally" is the brand name, never translated (plan 08 §3.7): verbatim, not a catalog key.
        .accessibilityLabel(role == .privacyCover ? Text(verbatim: "Tally") : Text(verbatim: ""))
        .accessibilityIdentifier(role == .privacyCover ? "privacy.cover" : "launch.placeholder")
    }

    private var backgroundColor: Color {
        role == .privacyCover ? TallyColor.bgBrand : TallyColor.bgCanvas
    }
}

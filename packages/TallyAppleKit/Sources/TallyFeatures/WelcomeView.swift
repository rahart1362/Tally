import SwiftUI
import TallyDesignSystem

/// The redesigned first-run welcome screen (ux-ui.md §3.2 stages 1-2, "Brand
/// moment" + "Value proposition"). A brand panel with the vector T-mark,
/// three benefit rows, the two entry actions, and the non-affiliation
/// footer required by app-store-compliance.md R10. No permission prompts,
/// no network calls, no sample or fixture data (UX-WP-01/03); the screens
/// the two buttons lead to are separate work packages (UX-WP-08, and the
/// app-core team's sample-data mode).
///
/// UX-WP-07 adds the brand-moment entrance: the T-mark rises and the navy
/// panel "blooms" out from behind it, then the wordmark and tagline fade in
/// — about 0.9 s, non-blocking, so every action below is live from the very
/// first frame (ux-ui.md: "non-blocking (the CTA is live from frame 1)").
/// Under Reduce Motion this becomes a single 0.2 s cross-fade with no scale
/// or translate ("Reduce Motion: 0.2 s cross-fade, no scale or translate").
/// Per ux-ui.md this plays "First run and after sign-out only": the root
/// route decides (`AppModel.playsBrandMoment`, passed in as
/// `playsBrandMoment`). When it must not play — back from sample data — the
/// view starts in its settled end state, so nothing animates.
struct WelcomeView: View {
    let onFindSchool: () -> Void
    let onExploreSampleData: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed: Bool

    init(playsBrandMoment: Bool = true, onFindSchool: @escaping () -> Void, onExploreSampleData: @escaping () -> Void) {
        self.onFindSchool = onFindSchool
        self.onExploreSampleData = onExploreSampleData
        // Already revealed = the end state from the first frame: `.onAppear`'s guard then skips
        // the entrance, and the `.animation(_:value:)` modifiers never see `revealed` change.
        _revealed = State(initialValue: !playsBrandMoment)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                brandPanel
                    .padding(.bottom, TallySpacing.xxl)

                benefitRows
                    .padding(.horizontal, TallySpacing.screenMargin)
                    .padding(.bottom, TallySpacing.xxl)

                actions // MUTATION M3: back in the scroll content, not pinned
                    .padding(.horizontal, TallySpacing.screenMargin)

                footer
                    .padding(.top, TallySpacing.md)
                    .padding(.horizontal, TallySpacing.screenMargin)
                    .padding(.bottom, TallySpacing.xxl)
            }
        }
        .background(TallyColor.bgCanvas)
        // perf-app-runtime.md §7 step 3: both entry actions are pinned above the bottom safe
        // area, so they are on screen and tappable from the first frame on every iPhone and at
        // every Dynamic Type size, whatever the scroll position. The R10 footer stays in the
        // scrolling content.
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard !revealed else { return }
            let motion = BrandMomentMotion.forReduceMotion(reduceMotion)
            withAnimation(motion.panelAnimation) { revealed = true }
        }
    }

    private var brandPanel: some View {
        let motion = BrandMomentMotion.forReduceMotion(reduceMotion)
        return VStack(spacing: TallySpacing.md) {
            TMark(size: 96)
                .padding(.top, TallySpacing.xxxl)
                .scaleEffect(revealed ? 1 : motion.markStartScale)
                .offset(y: revealed ? 0 : motion.markStartOffsetY)

            Text("Tally")
                .font(.system(.largeTitle, design: .serif).bold())
                .foregroundStyle(TallyColor.brandCream)
                .opacity(revealed ? 1 : 0)
                .animation(motion.wordmarkAnimation, value: revealed)

            Text("Every class, grade and deadline from Canvas — at a glance")
                .font(TallyTypography.body)
                .foregroundStyle(TallyColor.textOnHero2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TallySpacing.xxl)
                .padding(.bottom, TallySpacing.xxxl)
                .opacity(revealed ? 1 : 0)
                .animation(motion.wordmarkAnimation, value: revealed)
        }
        .frame(maxWidth: .infinity)
        .background(TallyColor.bgBrand.opacity(revealed ? 1 : 0))
    }

    private var benefitRows: some View {
        VStack(alignment: .leading, spacing: TallySpacing.lg) {
            BenefitRow(symbol: "chart.xyaxis.line", text: "See where you stand")
            BenefitRow(symbol: "bell", text: "Stay ahead of deadlines")
            BenefitRow(
                symbol: "checkmark.shield",
                text: "Private by design",
                detail: "No Tally account. Your data stays on this iPhone."
            )
        }
        .padding(.top, TallySpacing.xxl)
    }

    private var actions: some View {
        VStack(spacing: TallySpacing.md) {
            Button("Find My School", action: onFindSchool)
                .buttonStyle(.tallyPrimary)
                .frame(maxWidth: .infinity)

            Button("Explore with Sample Data", action: onExploreSampleData)
                .buttonStyle(.tallySecondary)
                .frame(maxWidth: .infinity)
        }
    }

    private var footer: some View {
        // app-store-compliance.md R10: the exact disclaimer wording, always
        // visible, never gated behind a tap.
        Text(
            "Tally is an independent app and is not affiliated with, endorsed by, " +
            "or sponsored by Instructure, Inc. Canvas is a trademark of Instructure, Inc."
        )
        .font(TallyTypography.caption)
        .foregroundStyle(TallyColor.textSecondary)
        .multilineTextAlignment(.center)
    }
}

private struct BenefitRow: View {
    let symbol: String
    let text: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: TallySpacing.md) {
            Image(systemName: symbol)
                .font(.system(.title3))
                .foregroundStyle(TallyColor.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: TallySpacing.xs) {
                Text(text)
                    .font(TallyTypography.cardTitle)
                    .foregroundStyle(TallyColor.textPrimary)
                if let detail {
                    Text(detail)
                        .font(TallyTypography.footnote)
                        .foregroundStyle(TallyColor.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Pure motion spec for the brand moment (ux-ui.md §3.2 stage 1), so both
/// variants are testable without a simulator (`@testable import
/// TallyFeatures`). `Animation` is `Equatable`, so the whole type is too.
struct BrandMomentMotion: Equatable {
    /// The T-mark's starting scale, before it "rises" to 1.
    let markStartScale: CGFloat
    /// The T-mark's starting vertical offset in points, before it settles to 0.
    let markStartOffsetY: CGFloat
    /// Drives the T-mark's rise and the panel's bloom (its background opacity).
    let panelAnimation: Animation
    /// Drives the wordmark and tagline fade-in, staggered after the panel
    /// under normal motion; simultaneous with everything else under Reduce Motion.
    let wordmarkAnimation: Animation

    static func forReduceMotion(_ reduceMotion: Bool) -> BrandMomentMotion {
        if reduceMotion {
            // "0.2 s cross-fade, no scale or translate": the mark never
            // moves or scales, so only opacity animates, once.
            let fade = Animation.easeInOut(duration: 0.2)
            return BrandMomentMotion(markStartScale: 1, markStartOffsetY: 0,
                                     panelAnimation: fade, wordmarkAnimation: fade)
        }
        // "About 0.9 s total": the mark rises and the panel blooms over the
        // first ~0.55 s, then the wordmark and tagline fade in over the rest.
        return BrandMomentMotion(
            markStartScale: 0.7, markStartOffsetY: 32,
            panelAnimation: .snappy(duration: 0.55),
            wordmarkAnimation: .easeIn(duration: 0.45).delay(0.35)
        )
    }
}

#Preview {
    RootView(appModel: AppModel())
}

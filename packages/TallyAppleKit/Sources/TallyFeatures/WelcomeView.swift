import SwiftUI
import TallyDesignSystem

/// The redesigned first-run welcome screen (ux-ui.md §3.2 stage 2, "Value
/// proposition"). Static layout only: a brand panel with the vector T-mark,
/// three benefit rows, the two entry actions, and the non-affiliation
/// footer required by app-store-compliance.md R10. No permission prompts,
/// no network calls, no sample or fixture data — this is the shell (UX-WP-01/03);
/// the screens the two buttons lead to are separate work packages.
struct WelcomeView: View {
    let onFindSchool: () -> Void
    let onExploreSampleData: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                brandPanel
                    .padding(.bottom, TallySpacing.xxl)

                benefitRows
                    .padding(.horizontal, TallySpacing.screenMargin)
                    .padding(.bottom, TallySpacing.xxl)

                actions
                    .padding(.horizontal, TallySpacing.screenMargin)

                footer
                    .padding(.top, TallySpacing.xxl)
                    .padding(.horizontal, TallySpacing.screenMargin)
                    .padding(.bottom, TallySpacing.xxl)
            }
        }
        .background(TallyColor.bgCanvas)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var brandPanel: some View {
        VStack(spacing: TallySpacing.md) {
            TMark(size: 96)
                .padding(.top, TallySpacing.xxxl)

            Text("Tally")
                .font(.system(.largeTitle, design: .serif).bold())
                .foregroundStyle(TallyColor.brandCream)

            Text("Every class, grade and deadline from Canvas — at a glance")
                .font(TallyTypography.body)
                .foregroundStyle(TallyColor.textOnHero2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TallySpacing.xxl)
                .padding(.bottom, TallySpacing.xxxl)
        }
        .frame(maxWidth: .infinity)
        .background(TallyColor.bgBrand)
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

#Preview {
    RootView()
}

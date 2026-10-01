import SwiftUI
import TallyDesignSystem
import TallyStrings

/// UX-WP-09: the sign-in hand-off screen (ux-ui.md §3.2 stage 4 / prototype
/// step 5). Sets expectations before any system UI appears, then starts the
/// real flow through `SignInHandoffViewModel`.
struct SignInHandoffView: View {
    @State private var viewModel: SignInHandoffViewModel
    let onChooseDifferentSchool: () -> Void

    init(viewModel: SignInHandoffViewModel, onChooseDifferentSchool: @escaping () -> Void) {
        _viewModel = State(wrappedValue: viewModel)
        self.onChooseDifferentSchool = onChooseDifferentSchool
    }

    var body: some View {
        ScrollView {
            VStack(spacing: TallySpacing.xl) {
                header
                statusBanner
                expectationCard
                Spacer(minLength: TallySpacing.xl)
                actions
            }
            .padding(TallySpacing.screenMargin)
        }
        .background(TallyColor.bgCanvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(spacing: TallySpacing.md) {
            TMark(size: 58)
            Text(L10n.Onboarding.SignIn.signInTo(viewModel.schoolDisplayName))
                .font(TallyTypography.screenTitle)
                .foregroundStyle(TallyColor.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Label(viewModel.host, systemImage: "building.columns")
                .font(TallyTypography.subheadline)
                .foregroundStyle(TallyColor.textSecondary)
                .padding(.horizontal, TallySpacing.md)
                .padding(.vertical, TallySpacing.xs)
                .background(TallyColor.bgCard, in: Capsule())
        }
        .padding(.top, TallySpacing.xl)
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch viewModel.phase {
        case .cancelledNotice:
            Text(L10n.Onboarding.SignIn.cancelledNotice())
                .font(TallyTypography.footnote)
                .foregroundStyle(TallyColor.textSecondary)
        case .failed(.accessDenied):
            InlineNotice(text: L10n.Onboarding.SignIn.accessDenied())
        case .failed(.networkFailure):
            InlineNotice(text: L10n.Onboarding.SignIn.networkFailure(viewModel.schoolDisplayName))
        case .failed(.other):
            InlineNotice(text: L10n.Onboarding.SignIn.otherFailure())
        case .idle, .presenting:
            EmptyView()
        }
    }

    /// The four expectation rows, copy verbatim from the prototype (`docs/pmo/ux/first-run-prototype.html`).
    private var expectationCard: some View {
        VStack(spacing: 0) {
            ExpectationRow(
                symbol: "key.fill",
                title: L10n.Onboarding.SignIn.expectation1Title(),
                detail: L10n.Onboarding.SignIn.expectation1Detail()
            )
            Divider().padding(.leading, TallySpacing.xxl + TallySpacing.md)
            ExpectationRow(
                symbol: "bubble.left.fill",
                title: L10n.Onboarding.SignIn.expectation2Title(),
                detail: L10n.Onboarding.SignIn.expectation2Detail(viewModel.host)
            )
            Divider().padding(.leading, TallySpacing.xxl + TallySpacing.md)
            ExpectationRow(
                symbol: "checkmark.shield.fill",
                title: L10n.Onboarding.SignIn.expectation3Title(),
                detail: L10n.Onboarding.SignIn.expectation3Detail()
            )
            Divider().padding(.leading, TallySpacing.xxl + TallySpacing.md)
            ExpectationRow(
                symbol: "arrow.uturn.left.circle.fill",
                title: L10n.Onboarding.SignIn.expectation4Title(),
                detail: L10n.Onboarding.SignIn.expectation4Detail()
            )
        }
        .padding(.vertical, TallySpacing.xs)
        .background(TallyColor.bgCard, in: RoundedRectangle(cornerRadius: TallyRadius.card, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: TallySpacing.md) {
            Button {
                Task { await viewModel.continueSigningIn() }
            } label: {
                HStack {
                    if viewModel.phase == .presenting { ProgressView().tint(TallyColor.accentOnFill) }
                    Text(L10n.Onboarding.SignIn.continueTo(viewModel.schoolDisplayName))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tallyPrimary)
            .disabled(viewModel.phase == .presenting)

            Button(String(localized: L10n.Onboarding.chooseDifferentSchool()), action: onChooseDifferentSchool)
                .buttonStyle(.tallySecondary)
                .frame(maxWidth: .infinity)
                .disabled(viewModel.phase == .presenting)
        }
    }
}

private struct ExpectationRow: View {
    let symbol: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        HStack(alignment: .top, spacing: TallySpacing.md) {
            Image(systemName: symbol)
                .font(.system(.title3))
                .foregroundStyle(TallyColor.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: TallySpacing.xs) {
                Text(title)
                    .font(TallyTypography.cardTitle)
                    .foregroundStyle(TallyColor.textPrimary)
                Text(detail)
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textSecondary)
            }
        }
        .padding(TallySpacing.md)
        .accessibilityElement(children: .combine)
    }
}

private struct InlineNotice: View {
    let text: LocalizedStringResource

    var body: some View {
        HStack(alignment: .top, spacing: TallySpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(TallyColor.accent)
            Text(text)
                .font(TallyTypography.footnote)
                .foregroundStyle(TallyColor.textPrimary)
        }
        .padding(TallySpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TallyColor.bgCard, in: RoundedRectangle(cornerRadius: TallyRadius.tile, style: .continuous))
    }
}

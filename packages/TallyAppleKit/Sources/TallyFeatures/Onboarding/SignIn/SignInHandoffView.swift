import SwiftUI
import TallyDesignSystem

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
            Text("Sign in to \(viewModel.schoolDisplayName)")
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
            Text("Sign-in cancelled. Nothing was shared.")
                .font(TallyTypography.footnote)
                .foregroundStyle(TallyColor.textSecondary)
        case .failed(.accessDenied):
            InlineNotice(text: "Tally needs read access to show your courses. You can try again any time.")
        case .failed(.networkFailure):
            InlineNotice(text: "Couldn't reach \(viewModel.schoolDisplayName). Check your connection and try again.")
        case .failed(.other):
            InlineNotice(text: "Something went wrong signing in. You can try again.")
        case .idle, .presenting:
            EmptyView()
        }
    }

    /// The four expectation rows, copy verbatim from the prototype (`docs/pmo/ux/first-run-prototype.html`).
    private var expectationCard: some View {
        VStack(spacing: 0) {
            ExpectationRow(
                symbol: "key.fill",
                title: "Use your usual school login",
                detail: "You sign in on your school's page. Tally never sees your password."
            )
            Divider().padding(.leading, TallySpacing.xxl + TallySpacing.md)
            ExpectationRow(
                symbol: "bubble.left.fill",
                title: "iOS will ask first",
                detail: "You'll see \u{201c}Tally Wants to Use \(viewModel.host) to Sign In\u{201d}. Choose Continue."
            )
            Divider().padding(.leading, TallySpacing.xxl + TallySpacing.md)
            ExpectationRow(
                symbol: "checkmark.shield.fill",
                title: "Approve read access",
                detail: "Canvas asks you to authorize Tally. Tally only reads your courses, grades and due dates."
            )
            Divider().padding(.leading, TallySpacing.xxl + TallySpacing.md)
            ExpectationRow(
                symbol: "arrow.uturn.left.circle.fill",
                title: "Then you're back here",
                detail: "Tally loads your courses straight away."
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
                    Text("Continue to \(viewModel.schoolDisplayName)")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tallyPrimary)
            .disabled(viewModel.phase == .presenting)

            Button("Choose a Different School", action: onChooseDifferentSchool)
                .buttonStyle(.tallySecondary)
                .frame(maxWidth: .infinity)
                .disabled(viewModel.phase == .presenting)
        }
    }
}

private struct ExpectationRow: View {
    let symbol: String
    let title: String
    let detail: String

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
    let text: String

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

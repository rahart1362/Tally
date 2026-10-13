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

    /// MVP-2b: the school's address is one long word, so it wrapped mid-word ("canvas.northfield.ex-
    /// / ample" at the default size, "can- / vas.north- / field.exam- / ple" at AX5, scope=a11y run
    /// 38338079168). Shown through `TallyTokenBreaks`, it wraps only at its dots; VoiceOver and
    /// the UI tests read the plain text (each element's own label).
    private var header: some View {
        VStack(spacing: TallySpacing.md) {
            TMark(size: 58)
            Text(L10n.Onboarding.SignIn.signInTo(TallyTokenBreaks.breakable(viewModel.schoolDisplayName)))
                .font(TallyTypography.screenTitle)
                .foregroundStyle(TallyColor.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityLabel(Text(L10n.Onboarding.SignIn.signInTo(viewModel.schoolDisplayName)))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("onboarding.signIn.title")

            SchoolAddressTag(host: viewModel.host)
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
                detail: L10n.Onboarding.SignIn.expectation2Detail(TallyTokenBreaks.breakable(viewModel.host)),
                spokenDetail: L10n.Onboarding.SignIn.expectation2Detail(viewModel.host)
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
                    // MVP-2b: wraps at the address's dots at the larger text sizes (`header`'s note).
                    Text(L10n.Onboarding.SignIn.continueTo(TallyTokenBreaks.breakable(viewModel.schoolDisplayName)))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tallyPrimary)
            .disabled(viewModel.phase == .presenting)
            // The plain text: `SignInSignOutUITests` and `PaywallUITests` find this button by it.
            .accessibilityLabel(Text(L10n.Onboarding.SignIn.continueTo(viewModel.schoolDisplayName)))
            // L10N-04: a stable id (the Audit tour looked this up by its English text —
            // "Continue to %@" — which Spanish changes to "Continuar a %@").
            .accessibilityIdentifier("onboarding.signIn.continueTo")

            Button(String(localized: L10n.Onboarding.chooseDifferentSchool()), action: onChooseDifferentSchool)
                .buttonStyle(.tallySecondary)
                .frame(maxWidth: .infinity)
                .disabled(viewModel.phase == .presenting)
                // MVP-2b: names it for its measured contrast waiver (`docs/pmo/a11y-waivers.md`).
                .accessibilityIdentifier("onboarding.signIn.chooseDifferentSchool")
        }
    }
}

/// The school's address under the title, as a tag.
///
/// MVP-2b (scope=a11y run 38338079168): Xcode's audit read the address alone as a label that "is
/// not human-readable", and at AX5 the capsule grew around four broken lines into an oval. Its
/// label is now "School" with the address as its value (VoiceOver: "School, canvas.northfield.
/// example"; "School" is Settings' existing row title), the address wraps only at its dots
/// (`TallyTokenBreaks`), and from AX1 up the tag is a rounded rectangle, which keeps its shape
/// around several lines, with the icon above the address so the address has the tag's full width
/// (run 38350587735: beside the icon, "northfield." filled the AX5 tag to its edge).
private struct SchoolAddressTag: View {
    let host: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = typeSize.isAccessibilitySize
            ? AnyShape(RoundedRectangle(cornerRadius: TallyRadius.tile, style: .continuous))
            : AnyShape(Capsule())
        content
            .font(TallyTypography.subheadline)
            .foregroundStyle(TallyColor.textSecondary)
            .padding(.horizontal, TallySpacing.md)
            .padding(.vertical, TallySpacing.xs)
            .background(TallyColor.bgCard, in: shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(L10n.Settings.schoolLabel()))
            .accessibilityValue(Text(verbatim: host))
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier("onboarding.signIn.school")
    }

    @ViewBuilder
    private var content: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: TallySpacing.xs) {
                icon
                address
            }
        } else {
            Label { address } icon: { icon }
        }
    }

    private var icon: some View {
        Image(systemName: "building.columns")
    }

    /// Shown with its break opportunities; its own label is the plain address (run 38350587735:
    /// the title and the button, whose labels are plain, cleared the audit's clipping check; this
    /// text and the expectation line, whose labels carried the invisible breaks, did not).
    private var address: some View {
        Text(verbatim: TallyTokenBreaks.breakable(host))
            .accessibilityLabel(Text(verbatim: host))
            .accessibilityIdentifier("onboarding.signIn.schoolText")
    }
}

private struct ExpectationRow: View {
    let symbol: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource
    /// MVP-2b: what VoiceOver reads for `detail` when it differs from what is drawn (the school
    /// address drawn with break opportunities, `TallyTokenBreaks`; read plain).
    var spokenDetail: LocalizedStringResource?

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
                    .accessibilityLabel(Text(spokenDetail ?? detail))
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

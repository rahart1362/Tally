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
        // UX1-04/UX1-09: the default (centre) alignment let each row's HStack size to its own
        // intrinsic width, so the icon column zig-zagged and the dividers (inset to the icon
        // column's fixed offset) no longer lined up under it. `.leading` plus a full-width row
        // frame keeps one shared left edge for icon, text and divider.
        VStack(alignment: .leading, spacing: 0) {
            ExpectationRow(
                symbol: "key.fill",
                title: L10n.Onboarding.SignIn.expectation1Title(),
                detail: L10n.Onboarding.SignIn.expectation1Detail()
            )
            // UX1-04: a stable id per row (`SignInSignOutUITests` checks each one still exists;
            // a `frame.minX` equality check was tried and dropped — the combined element's
            // reported frame is the union of its icon/title/detail content bounds, not the
            // row's stretched layout frame, so it varies with each row's own text and glyph
            // regardless of whether the rows share a left edge).
            .accessibilityIdentifier("onboarding.signIn.expectation1")
            Divider().padding(.leading, ExpectationRow.dividerInset)
            ExpectationRow(
                symbol: "bubble.left.fill",
                title: L10n.Onboarding.SignIn.expectation2Title(),
                detail: L10n.Onboarding.SignIn.expectation2Detail(viewModel.host)
            )
            .accessibilityIdentifier("onboarding.signIn.expectation2")
            Divider().padding(.leading, ExpectationRow.dividerInset)
            ExpectationRow(
                symbol: "checkmark.shield.fill",
                title: L10n.Onboarding.SignIn.expectation3Title(),
                detail: L10n.Onboarding.SignIn.expectation3Detail()
            )
            .accessibilityIdentifier("onboarding.signIn.expectation3")
            Divider().padding(.leading, ExpectationRow.dividerInset)
            ExpectationRow(
                symbol: "arrow.uturn.left.circle.fill",
                title: L10n.Onboarding.SignIn.expectation4Title(),
                detail: L10n.Onboarding.SignIn.expectation4Detail()
            )
            .accessibilityIdentifier("onboarding.signIn.expectation4")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
/// around several lines (run 38350587735, AX5: "canvas." / "northfield." / "example", whole).
private struct SchoolAddressTag: View {
    let host: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = typeSize.isAccessibilitySize
            ? AnyShape(RoundedRectangle(cornerRadius: TallyRadius.tile, style: .continuous))
            : AnyShape(Capsule())
        Label { address } icon: { Image(systemName: "building.columns") }
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

    /// Shown with its break opportunities; its own label is the plain address, as the title's
    /// and the button's are. (Run 38357314250: stacking the icon above it at the AX sizes made the
    /// audit lose the text when it grew it, an unattributable "may be clipped"; reverted.)
    private var address: some View {
        Text(verbatim: TallyTokenBreaks.breakable(host))
            .accessibilityLabel(Text(verbatim: host))
            .accessibilityIdentifier("onboarding.signIn.schoolText")
    }
}

private struct ExpectationRow: View {
    /// Welcome's `BenefitRow` and School search's hint row use the same 28 pt icon column
    /// (UX1-09); named once so the divider inset below can be derived from it instead of a
    /// second magic number that silently drifts from the row's own padding.
    static let iconWidth: CGFloat = 28
    static var dividerInset: CGFloat { TallySpacing.md + iconWidth + TallySpacing.md }

    let symbol: String
    let title: LocalizedStringResource
    let detail: LocalizedStringResource

    var body: some View {
        HStack(alignment: .top, spacing: TallySpacing.md) {
            Image(systemName: symbol)
                .font(.system(.title3))
                .foregroundStyle(TallyColor.accent)
                .frame(width: Self.iconWidth)
            VStack(alignment: .leading, spacing: TallySpacing.xs) {
                Text(title)
                    .font(TallyTypography.cardTitle)
                    .foregroundStyle(TallyColor.textPrimary)
                Text(detail)
                    .font(TallyTypography.footnote)
                    .foregroundStyle(TallyColor.textSecondary)
            }
        }
        // UX1-04: without this, the row sizes to its own text and the parent VStack's
        // `.leading` alignment still left-aligns each row's *own* bounding box, which is no
        // better than centring once rows are different widths. Stretching every row to the
        // card's full width is what gives the icon column one shared x position.
        .frame(maxWidth: .infinity, alignment: .leading)
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

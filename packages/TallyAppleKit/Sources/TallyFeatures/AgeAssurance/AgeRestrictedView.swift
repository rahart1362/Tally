import SwiftUI
import TallyDesignSystem
import TallyDomain
import TallyStrings

/// AGE-1 (EB-01(e)/EB-02(b)): "show a neutral screen and keep data hidden until Apple reports
/// consent." Deliberately has no "Continue" or "Not Now" escape — unlike
/// `SchoolRevokedNoticeView`, which protects a different, non-legal-compliance scenario, this
/// screen's whole purpose is to block until Apple's own signal (`AgeAssuranceModel.gateDecision`)
/// says otherwise. `RootView` presents it over the signed-in Home only (never Welcome or Sample
/// Data, which have no account data to hide, and never in place of Apple's own launch block —
/// EB-04 is that block, verified on a device, not this screen).
struct AgeRestrictedView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: TallySpacing.xl) {
                Image(systemName: "hourglass")
                    .font(TallyTypography.screenTitle)
                    .foregroundStyle(TallyColor.accent)
                    .accessibilityHidden(true)
                Text(L10n.AgeAssurance.restrictedTitle())
                    .font(TallyTypography.sectionHeader)
                    .foregroundStyle(TallyColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("ageRestricted.title")
                Text(L10n.AgeAssurance.restrictedBody())
                    .font(TallyTypography.body)
                    .foregroundStyle(TallyColor.textSecondary)
                    .accessibilityIdentifier("ageRestricted.body")
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(TallySpacing.xl)
            .frame(maxWidth: .infinity)
        }
        .background(TallyColor.bgCanvas)
        .accessibilityIdentifier("ageRestricted.screen")
    }
}

/// Presents `AgeRestrictedView` full screen while `appModel.ageAssurance.gateDecision ==
/// .restrictedPendingConsent`, in a view of its own behind the Home — the same shape
/// `SchoolRevokedNoticePresenter` uses, so the two presentations never share a presenter.
struct AgeRestrictedPresenter: View {
    let appModel: AppModel

    var body: some View {
        Color.clear
            .fullScreenCover(isPresented: Binding(
                get: { appModel.ageAssurance.gateDecision == .restrictedPendingConsent },
                set: { _ in } // no user action closes this; only a new `consentOutcome` does.
            )) {
                AgeRestrictedView()
            }
    }
}

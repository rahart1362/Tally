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
        // UX2-04/UX2-09: the icon/title/centring this screen built by hand (a bare `ScrollView`
        // with no toolbar, so scrolled text ran under the status bar at AX5 -- the D01 class of
        // defect) are now the shared `TallyNoticeLayout`, which also carries UX2-04's opaque
        // status-bar band and the `screenMargin` sides this screen's own `TallySpacing.xl` padding
        // used instead.
        TallyNoticeLayout(systemImage: "hourglass",
                          title: Text(L10n.AgeAssurance.restrictedTitle()),
                          titleIdentifier: "ageRestricted.title") {
            Text(L10n.AgeAssurance.restrictedBody())
                .font(TallyTypography.body)
                .foregroundStyle(TallyColor.textSecondary)
                .accessibilityIdentifier("ageRestricted.body")
        }
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

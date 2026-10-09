import SwiftUI
import TallyDesignSystem
import TallyStrings

/// "School found but not enabled" (ux-ui.md §3.2.1): a full screen, never a
/// broken login, when a search result or typed address has no
/// `ClientRegistry` entry. Offers **Ask My School** (a share sheet with
/// pre-written admin-facing text) and **Explore with Sample Data**. The
/// spec's third, conditional action ("Use Calendar-Only Mode") depends on
/// security.md decision SEC-D2(i), which is not adopted, so it is
/// deliberately omitted here rather than half-built.
///
/// X-1 (plan 08, owner-approved 2026-09-30): the admin request text used to say "It's a free app";
/// Tally is a paid subscription (P1), so it now says "It's an app".
struct SchoolNotEnabledView: View {
    let school: String
    let onExploreSampleData: () -> Void

    private var adminRequestText: String {
        String(localized: L10n.Onboarding.SchoolSearch.adminRequestText(school: school, domain: TallyOrgDomainInfo.current))
    }

    var body: some View {
        TallyUnavailableView(Text(L10n.Onboarding.SchoolSearch.notEnabledTitle(school: school)), systemImage: "building.columns",
                             description: Text(L10n.Onboarding.SchoolSearch.notEnabledDescription())) {
            VStack(spacing: TallySpacing.md) {
                ShareLink(item: adminRequestText) {
                    Label(String(localized: L10n.Onboarding.SchoolSearch.askMySchool()), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tallyPrimary)

                Button(String(localized: L10n.Account.exploreWithSampleData()), action: onExploreSampleData)
                    .buttonStyle(.tallySecondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, TallySpacing.xxl)
            .padding(.top, TallySpacing.md)
        }
        // ux-fp2 D20: centred when it fits, scrolling when it does not (AX5), with the D01
        // chrome, since it can now scroll under the bar.
        .tallyCenteredScrolling()
        .tallyScreenChrome()
        .background(TallyColor.bgCanvas)
        .navigationTitle(Text(L10n.Onboarding.SchoolSearch.notAvailableYetNavTitle()))
        .navigationBarTitleDisplayMode(.inline)
    }
}

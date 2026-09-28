import SwiftUI
import TallyDesignSystem

/// "School found but not enabled" (ux-ui.md §3.2.1): a full screen, never a
/// broken login, when a search result or typed address has no
/// `ClientRegistry` entry. Offers **Ask My School** (a share sheet with
/// pre-written admin-facing text) and **Explore with Sample Data**. The
/// spec's third, conditional action ("Use Calendar-Only Mode") depends on
/// security.md decision SEC-D2(i), which is not adopted, so it is
/// deliberately omitted here rather than half-built.
struct SchoolNotEnabledView: View {
    let school: String
    let onExploreSampleData: () -> Void

    private var adminRequestText: String {
        "Would you consider enabling Tally at \(school)? It's a free app that shows students " +
        "their Canvas courses, grades and due dates. There's no Tally server and no student " +
        "accounts — Tally signs in directly with your Canvas, the same way a browser does. " +
        "Setup takes a Canvas admin a few minutes: https://\(TallyOrgDomainInfo.current)/admin"
    }

    var body: some View {
        ContentUnavailableView {
            Label("Tally isn't available at \(school) yet", systemImage: "building.columns")
        } description: {
            Text("Your school's Canvas admin needs to approve Tally.")
        } actions: {
            VStack(spacing: TallySpacing.md) {
                ShareLink(item: adminRequestText) {
                    Label("Ask My School", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tallyPrimary)

                Button("Explore with Sample Data", action: onExploreSampleData)
                    .buttonStyle(.tallySecondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, TallySpacing.xxl)
            .padding(.top, TallySpacing.md)
        }
        .background(TallyColor.bgCanvas)
        .navigationTitle("Not available yet")
        .navigationBarTitleDisplayMode(.inline)
    }
}

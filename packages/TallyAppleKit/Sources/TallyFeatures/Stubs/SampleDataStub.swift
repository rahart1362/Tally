import SwiftUI
import TallyDesignSystem

/// Placeholder destination for "Explore with Sample Data". The real demo
/// mode (app-store-compliance.md §3.2 option B: the full app running over
/// bundled synthetic fixtures, with a persistent "Sample data" banner) is a
/// separate work package; this stub only proves the navigation wiring, and
/// deliberately shows no data, sample or otherwise.
struct SampleDataStub: View {
    var body: some View {
        ContentUnavailableView(
            "Sample data mode",
            systemImage: "sparkles",
            description: Text("The guided sample-data tour lands in a later milestone.")
        )
        .background(TallyColor.bgCanvas)
        .navigationTitle("Explore with Sample Data")
        .navigationBarTitleDisplayMode(.large)
    }
}

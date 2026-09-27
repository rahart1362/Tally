import SwiftUI
import TallyDesignSystem

/// Placeholder destination for "Find My School". The real school-search
/// screen (ux-ui.md §3.2.1: debounced search, institution registry lookup,
/// "not enabled at your school" state) is a separate work package; this
/// stub only proves the navigation wiring, with no fixture or fake search
/// results.
struct FindSchoolStub: View {
    var body: some View {
        ContentUnavailableView(
            "Find your school",
            systemImage: "building.columns",
            description: Text("School search lands in a later milestone.")
        )
        .background(TallyColor.bgCanvas)
        .navigationTitle("Find your school")
        .navigationBarTitleDisplayMode(.large)
    }
}

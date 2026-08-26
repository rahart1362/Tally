import SwiftUI
import TallyDesignSystem

public struct InsightsView: View {
    public init() {}
    public var body: some View {
        NavigationView {
            Text("Insights")
                .font(.Tally.title)
                .navigationTitle("Insights")
        }
    }
}

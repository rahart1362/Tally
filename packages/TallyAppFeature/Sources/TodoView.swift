import SwiftUI
import TallyDesignSystem

public struct TodoView: View {
    public init() {}
    public var body: some View {
        NavigationView {
            Text("Todo")
                .font(.Tally.title)
                .navigationTitle("Todo")
        }
    }
}

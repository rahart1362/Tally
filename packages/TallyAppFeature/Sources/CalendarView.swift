import SwiftUI
import TallyDesignSystem

public struct CalendarView: View {
    public init() {}
    public var body: some View {
        NavigationView {
            Text("Calendar")
                .font(.Tally.title)
                .navigationTitle("Calendar")
        }
    }
}

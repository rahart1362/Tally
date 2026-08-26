import SwiftUI
import TallyDesignSystem

public struct CoursesView: View {
    public init() {}
    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: Spacing.md) {
                    ForEach(["Calculus I", "Intro to Biology", "World History"], id: \.self) { course in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(course).font(.Tally.headline)
                                Text("Next due: Friday").font(.Tally.caption).foregroundColor(.Tally.textSecondary)
                            }
                            Spacer()
                            Text("A").font(.Tally.title2).foregroundColor(.Tally.primary)
                        }
                        .tallyCardStyle()
                    }
                }
                .padding()
            }
            .background(Color.Tally.background.ignoresSafeArea())
            .navigationTitle("Courses")
        }
    }
}

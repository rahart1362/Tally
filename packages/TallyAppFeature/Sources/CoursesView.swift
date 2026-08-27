import SwiftUI
import TallyDesignSystem

public struct CoursesView: View {
    @StateObject private var viewModel = CoursesViewModel()
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                headerView
                
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.courses) { course in
                            NavigationLink(destination: LazyView(CourseDetailView(course: course))) {
                                courseCard(course)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding()
                }
            }
            .padding(.top, 16)
            .background(
                VStack(spacing: 0) {
                    Color.Tally.navyBackground
                        .frame(height: 150)
                    Color.Tally.lightGrayBg
                }
                .ignoresSafeArea()
            )
            .navigationBarHidden(true)
        }
    }
    
    private var headerView: some View {
        HStack {
            Button(action: {}) {
                HStack {
                    Text(viewModel.term)
                        .font(.Tally.title2)
                        .foregroundColor(Color.Tally.cardBackground)
                    Image(systemName: "chevron.down")
                        .foregroundColor(Color.Tally.cardBackground)
                }
            }
            Spacer()
            Button(action: {}) {
                Image(systemName: "plus")
                    .font(.title2)
                    .foregroundColor(Color.Tally.cardBackground)
            }
        }
        .padding(.horizontal)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }
    
    private func courseCard(_ course: CourseItem) -> some View {
        HStack(spacing: 0) {
            // Left color border
            Rectangle()
                .fill(course.color)
                .frame(width: 4)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(course.color.opacity(0.2))
                            .frame(width: 40, height: 40)
                        Image(systemName: course.icon)
                            .foregroundColor(course.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(course.name)
                            .font(.Tally.headline)
                            .foregroundColor(Color.Tally.textPrimary)
                        Text(course.code)
                            .font(.Tally.subheadline)
                            .foregroundColor(Color.Tally.textSecondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(course.gradeLetter)
                            .font(.Tally.title)
                            .foregroundColor(course.color)
                        Text(String(format: "%.1f%%", course.percentage))
                            .font(.Tally.caption)
                            .foregroundColor(Color.Tally.textSecondary)
                    }
                }
                
                Divider()
                
                HStack {
                    Text("Next:")
                        .font(.Tally.caption)
                        .foregroundColor(Color.Tally.textSecondary)
                    Text(course.nextAssignment)
                        .font(.Tally.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Color.Tally.textPrimary)
                    Spacer()
                    Text(course.dueDate)
                        .font(.Tally.caption)
                        .foregroundColor(Color.Tally.textSecondary)
                }
            }
            .padding(16)
        }
        .background(Color.Tally.cardBackground)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

/// Defers body evaluation until the view is actually rendered.
/// Prevents NavigationLink from eagerly instantiating destination views and their @StateObject properties.
struct LazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    var body: Content {
        build()
    }
}

import SwiftUI
import TallyDesignSystem

public struct CourseDetailView: View {
    let course: CourseItem
    @StateObject private var viewModel = CourseDetailViewModel()
    @Environment(\.presentationMode) var presentationMode
    
    public init(course: CourseItem) {
        self.course = course
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            headerView
            
            ScrollView {
                VStack(spacing: 24) {
                    tabBar
                    
                    assignmentsSection
                    
                    gradeDistributionSection
                    
                    whatIfSection
                }
                .padding()
            }
            .background(Color.Tally.lightGrayBg)
        }
        .navigationBarHidden(true)
    }
    
    private var headerView: some View {
        VStack(spacing: 20) {
            HStack {
                Button(action: { presentationMode.wrappedValue.dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(course.name)
                            .font(.Tally.headline)
                    }
                    .foregroundColor(Color.Tally.cardBackground)
                }
                Spacer()
                HStack(spacing: 16) {
                    Image(systemName: "star")
                        .foregroundColor(Color.Tally.brandGold)
                    Image(systemName: "ellipsis")
                        .foregroundColor(Color.Tally.cardBackground)
                }
            }
            
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(course.gradeLetter)
                        .font(.system(size: 60, weight: .bold))
                        .foregroundColor(Color.Tally.cardBackground)
                    HStack {
                        Text(String(format: "%.1f%%", course.percentage))
                            .font(.Tally.title2)
                            .foregroundColor(Color.Tally.cardBackground)
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up.right")
                            Text("+6.3%")
                        }
                        .font(.Tally.subheadline)
                        .foregroundColor(Color.Tally.psychologyGreen)
                    }
                }
                Spacer()
                // Sparkline placeholder
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 40))
                    path.addCurve(to: CGPoint(x: 100, y: 10), control1: CGPoint(x: 30, y: 40), control2: CGPoint(x: 70, y: 10))
                }
                .stroke(Color.white.opacity(0.8), lineWidth: 2)
                .frame(width: 100, height: 50)
            }
        }
        .padding()
        .padding(.top, 40) // Status bar padding approx
        .background(Color.Tally.navyBackground)
    }
    
    private var tabBar: some View {
        HStack(spacing: 20) {
            Text("Overview")
                .font(.Tally.subheadline)
                .foregroundColor(Color.Tally.textPrimary)
                .padding(.bottom, 8)
                .overlay(Rectangle().fill(course.color).frame(height: 2), alignment: .bottom)
            
            Text("Assignments")
                .font(.Tally.subheadline)
                .foregroundColor(Color.Tally.textSecondary)
                .padding(.bottom, 8)
            
            Text("Grades")
                .font(.Tally.subheadline)
                .foregroundColor(Color.Tally.textSecondary)
                .padding(.bottom, 8)
            
            Text("People")
                .font(.Tally.subheadline)
                .foregroundColor(Color.Tally.textSecondary)
                .padding(.bottom, 8)
            Spacer()
        }
    }
    
    private var assignmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Assignments")
                .font(.Tally.title2)
            
            ForEach(viewModel.assignments) { assignment in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(assignment.title)
                            .font(.Tally.headline)
                        Text(assignment.date)
                            .font(.Tally.caption)
                            .foregroundColor(Color.Tally.textSecondary)
                    }
                    Spacer()
                    Text(assignment.scoreText)
                        .font(.Tally.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(assignment.isGoodScore ? Color.Tally.psychologyGreen.opacity(0.2) : Color.Tally.alertRed.opacity(0.2))
                        .foregroundColor(assignment.isGoodScore ? Color.Tally.psychologyGreen : Color.Tally.alertRed)
                        .cornerRadius(8)
                }
                .tallyCardStyle()
            }
        }
    }
    
    private var gradeDistributionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Grade Distribution")
                .font(.Tally.title2)
            
            VStack {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(0..<10) { i in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(i == 8 ? course.color : Color.Tally.divider)
                            .frame(height: CGFloat(Int.random(in: 20...100)))
                    }
                }
                .frame(height: 120)
                HStack {
                    Text("Class Avg: 82%")
                        .font(.Tally.caption)
                        .foregroundColor(Color.Tally.textSecondary)
                    Spacer()
                    Text("You: \(String(format: "%.0f%%", course.percentage))")
                        .font(.Tally.caption)
                        .foregroundColor(course.color)
                        .fontWeight(.bold)
                }
            }
            .tallyCardStyle()
        }
    }
    
    private var whatIfSection: some View {
        HStack {
            Image(systemName: "function")
                .foregroundColor(course.color)
                .font(.title2)
            Text("What If? Calculator")
                .font(.Tally.headline)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundColor(Color.Tally.textSecondary)
        }
        .tallyCardStyle()
    }
}

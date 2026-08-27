import SwiftUI
import TallyDesignSystem

public struct InsightsView: View {
    @StateObject private var viewModel = InsightsViewModel()
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Insights")
                        .font(.Tally.title)
                        .foregroundColor(Color.Tally.cardBackground)
                    Spacer()
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 22))
                            .foregroundColor(Color.Tally.cardBackground)
                    }
                }
                .padding()
                
                ScrollView {
                    VStack(spacing: 20) {
                        performanceTrendCard
                        
                        HStack(spacing: 20) {
                            categoryBreakdownCard
                            studyStreakCard
                        }
                    }
                    .padding()
                }
            }
            .padding(.top, 16)
            .background(
                VStack(spacing: 0) {
                    Color.Tally.navyBackground
                        .frame(height: 100)
                    Color.Tally.lightGrayBg
                }
                .ignoresSafeArea()
            )
            .toolbar(.hidden, for: .navigationBar)
        }
    }
    
    private var performanceTrendCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance Trend")
                .font(.Tally.title2)
            
            // Mock Line Chart
            ZStack {
                VStack {
                    ForEach(["100", "80", "60", "40"], id: \.self) { val in
                        HStack {
                            Text(val)
                                .font(.Tally.caption)
                                .foregroundColor(Color.Tally.textSecondary)
                                .frame(width: 30, alignment: .trailing)
                            Rectangle()
                                .fill(Color.Tally.divider)
                                .frame(height: 1)
                        }
                        if val != "40" { Spacer() }
                    }
                }
                .frame(height: 150)
                
                Path { path in
                    path.move(to: CGPoint(x: 40, y: 130))
                    path.addLine(to: CGPoint(x: 100, y: 80))
                    path.addLine(to: CGPoint(x: 160, y: 100))
                    path.addLine(to: CGPoint(x: 220, y: 40))
                    path.addLine(to: CGPoint(x: 280, y: 20))
                }
                .stroke(Color.Tally.calculusBlue, lineWidth: 3)
            }
            
            HStack {
                Text("Sep")
                Spacer()
                Text("Oct")
                Spacer()
                Text("Nov")
                Spacer()
                Text("Dec")
            }
            .font(.Tally.caption)
            .foregroundColor(Color.Tally.textSecondary)
            .padding(.leading, 40)
        }
        .tallyCardStyle()
    }
    
    private var categoryBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Breakdown")
                .font(.Tally.headline)
            
            ZStack {
                Circle()
                    .stroke(Color.Tally.divider, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: 0.4)
                    .stroke(Color.Tally.biologyPurple, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                Circle()
                    .trim(from: 0.4, to: 0.7)
                    .stroke(Color.Tally.calculusBlue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                Circle()
                    .trim(from: 0.7, to: 0.9)
                    .stroke(Color.Tally.historyOrange, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                Circle()
                    .trim(from: 0.9, to: 1.0)
                    .stroke(Color.Tally.psychologyGreen, style: StrokeStyle(lineWidth: 10, lineCap: .round))
            }
            .frame(height: 80)
            
            VStack(alignment: .leading, spacing: 4) {
                legendItem(color: Color.Tally.biologyPurple, label: "Assign 40%")
                legendItem(color: Color.Tally.calculusBlue, label: "Exams 30%")
                legendItem(color: Color.Tally.historyOrange, label: "Quizzes 20%")
                legendItem(color: Color.Tally.psychologyGreen, label: "Discuss 10%")
            }
        }
        .tallyCardStyle()
    }
    
    private func legendItem(color: Color, label: String) -> some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 10)).foregroundColor(Color.Tally.textSecondary)
        }
    }
    
    private var studyStreakCard: some View {
        VStack(spacing: 12) {
            Text("Study Streak")
                .font(.Tally.headline)
            
            Text("🔥")
                .font(.system(size: 40))
            
            HStack(spacing: 4) {
                Text("\(viewModel.studyStreakDays)")
                    .font(.Tally.title)
                    .foregroundColor(Color.Tally.historyOrange)
                Text("days")
                    .font(.Tally.subheadline)
                    .foregroundColor(Color.Tally.textSecondary)
                    .offset(y: 4)
            }
        }
        .frame(maxWidth: .infinity)
        .tallyCardStyle()
    }
}


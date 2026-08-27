import SwiftUI
import TallyDesignSystem

public struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                // Background
                VStack(spacing: 0) {
                    Color.Tally.navyBackground
                        .frame(height: 300)
                        .ignoresSafeArea()
                    Color.Tally.lightGrayBg
                        .ignoresSafeArea()
                }
                
                ScrollView {
                    LazyVStack(spacing: 24) {
                        headerView
                        
                        overallGradeCard
                        
                        alertsSection
                        
                        scheduleSection
                    }
                    .padding(.horizontal)
                }
            }
            .navigationBarHidden(true)
        }
    }
    
    private var headerView: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tally")
                    .font(.custom("Georgia", size: 28))
                    .foregroundColor(Color.Tally.brandGold)
                    .fontWeight(.bold)
                Text("Good morning, Alex 👋")
                    .font(.Tally.title2)
                    .foregroundColor(Color.Tally.cardBackground)
                Text(Date().formatted(date: .abbreviated, time: .omitted))
                    .font(.Tally.subheadline)
                    .foregroundColor(Color.Tally.cardBackground.opacity(0.7))
            }
            Spacer()
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 24))
                    .foregroundColor(Color.Tally.cardBackground)
                Circle()
                    .fill(Color.Tally.alertRed)
                    .frame(width: 10, height: 10)
                    .offset(x: -2, y: 2)
            }
        }
        .padding(.top, 20)
    }
    
    private var overallGradeCard: some View {
        VStack {
            HStack {
                Text("Overall Standing")
                    .font(.Tally.headline)
                    .foregroundColor(Color.Tally.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .foregroundColor(Color.Tally.textSecondary)
            }
            
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.Tally.divider, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: viewModel.overallGradePercentage / 100.0)
                        .stroke(Color.Tally.brandGold, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack {
                        Text(viewModel.overallGradeLetter)
                            .font(.system(size: 40, weight: .bold))
                        Text(String(format: "%.1f%%", viewModel.overallGradePercentage))
                            .font(.Tally.caption)
                            .foregroundColor(Color.Tally.textSecondary)
                    }
                }
                .frame(width: 120, height: 120)
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "arrow.up.right")
                            .foregroundColor(Color.Tally.psychologyGreen)
                        Text("+\(String(format: "%.1f", viewModel.trend))%")
                            .foregroundColor(Color.Tally.psychologyGreen)
                            .fontWeight(.bold)
                        Text("vs last month")
                            .font(.Tally.caption)
                            .foregroundColor(Color.Tally.textSecondary)
                    }
                    // Mock sparkline placeholder
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 30))
                        path.addCurve(to: CGPoint(x: 100, y: 0), control1: CGPoint(x: 30, y: 30), control2: CGPoint(x: 70, y: 0))
                    }
                    .stroke(Color.Tally.brandGold, lineWidth: 2)
                    .frame(height: 30)
                }
            }
            .padding(.vertical, 10)
        }
        .tallyCardStyle()
    }
    
    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Alerts")
                .font(.Tally.title2)
                .foregroundColor(Color.Tally.textPrimary)
            
            ForEach(viewModel.alerts) { alert in
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(alert.type.color)
                            .frame(width: 40, height: 40)
                        Text("\(alert.count)")
                            .foregroundColor(.white)
                            .fontWeight(.bold)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(alert.title)
                            .font(.Tally.headline)
                            .foregroundColor(Color.Tally.textPrimary)
                        Text(alert.subtitle)
                            .font(.Tally.subheadline)
                            .foregroundColor(Color.Tally.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(Color.Tally.textSecondary)
                }
                .tallyCardStyle()
            }
        }
    }
    
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Schedule")
                .font(.Tally.title2)
                .foregroundColor(Color.Tally.textPrimary)
            
            VStack(spacing: 0) {
                ForEach(viewModel.schedule) { item in
                    HStack(alignment: .top, spacing: 16) {
                        Text(item.time)
                            .font(.Tally.subheadline)
                            .foregroundColor(Color.Tally.textSecondary)
                            .frame(width: 70, alignment: .trailing)
                        
                        ZStack(alignment: .top) {
                            Rectangle()
                                .fill(item.color.opacity(0.3))
                                .frame(width: 2)
                            Circle()
                                .fill(item.color)
                                .frame(width: 10, height: 10)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.courseName)
                                .font(.Tally.headline)
                                .foregroundColor(Color.Tally.textPrimary)
                            Text("\(item.type) • \(item.location)")
                                .font(.Tally.caption)
                                .foregroundColor(Color.Tally.textSecondary)
                        }
                        .padding(.bottom, 24)
                        
                        Spacer()
                    }
                }
            }
            .padding(.top, 8)
        }
    }
}

public extension Font.Tally {
    static let subheadline = Font.system(.subheadline, weight: .regular)
}

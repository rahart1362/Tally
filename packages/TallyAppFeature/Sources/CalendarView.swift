import SwiftUI
import TallyDesignSystem

public struct CalendarView: View {
    @StateObject private var viewModel = CalendarViewModel()
    
    public init() {}
    
    public var body: some View {
        NavigationView {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    headerView
                    weekStrip
                    
                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            timelineGrid
                            eventsOverlay
                        }
                        .padding(.top, 20)
                    }
                    .background(Color.Tally.cardBackground)
                }
                
                // FAB
                Button(action: {}) {
                    Image(systemName: "plus")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Color.Tally.navyBackground)
                        .clipShape(Circle())
                        .shadow(radius: 4, y: 4)
                }
                .padding()
            }
            .navigationBarHidden(true)
            .background(Color.Tally.lightGrayBg.ignoresSafeArea())
        }
    }
    
    private var headerView: some View {
        HStack {
            Button(action: {}) {
                HStack {
                    Text(viewModel.monthYear)
                        .font(.Tally.title2)
                        .foregroundColor(Color.Tally.textPrimary)
                    Image(systemName: "chevron.down")
                        .foregroundColor(Color.Tally.textPrimary)
                }
            }
            Spacer()
        }
        .padding()
        .background(Color.Tally.lightGrayBg)
    }
    
    private var weekStrip: some View {
        HStack {
            ForEach(["S","M","T","W","T","F","S"].enumerated().map({$0}), id: \.offset) { index, day in
                VStack(spacing: 8) {
                    Text(day)
                        .font(.Tally.caption)
                        .foregroundColor(Color.Tally.textSecondary)
                    Text("\(10 + index)")
                        .font(.Tally.subheadline)
                        .fontWeight(index == 2 ? .bold : .regular)
                        .foregroundColor(index == 2 ? .white : Color.Tally.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(index == 2 ? Color.Tally.navyBackground : Color.clear)
                        .clipShape(Circle())
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.bottom, 10)
        .background(Color.Tally.lightGrayBg)
    }
    
    private var timelineGrid: some View {
        VStack(spacing: 0) {
            ForEach(8...16, id: \.self) { hour in
                HStack(alignment: .top) {
                    Text("\(hour > 12 ? hour - 12 : hour) \(hour >= 12 ? "PM" : "AM")")
                        .font(.Tally.caption)
                        .foregroundColor(Color.Tally.textSecondary)
                        .frame(width: 50, alignment: .trailing)
                        .offset(y: -8)
                    
                    Rectangle()
                        .fill(Color.Tally.divider)
                        .frame(height: 1)
                }
                .frame(height: 60) // 1 hour = 60 points
            }
        }
    }
    
    private var eventsOverlay: some View {
        GeometryReader { geo in
            ForEach(viewModel.events) { event in
                let yOffset = (event.startHour - 8.0) * 60.0
                let height = event.durationHours * 60.0
                
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(event.color)
                        .frame(width: 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.courseName)
                            .font(.Tally.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(Color.Tally.textPrimary)
                        Text("\(event.type) • \(event.location)")
                            .font(.Tally.caption)
                            .foregroundColor(Color.Tally.textSecondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(event.color.opacity(0.15))
                }
                .cornerRadius(4)
                .frame(width: geo.size.width - 70, height: height)
                .offset(x: 60, y: yOffset)
            }
            
            // Current time line (mocked at ~10:30)
            HStack(spacing: 0) {
                Circle()
                    .fill(Color.Tally.alertRed)
                    .frame(width: 8, height: 8)
                    .offset(x: -4)
                Rectangle()
                    .fill(Color.Tally.alertRed)
                    .frame(height: 2)
            }
            .offset(x: 60, y: (10.5 - 8.0) * 60.0)
        }
    }
}

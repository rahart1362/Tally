import SwiftUI
import TallyDesignSystem

public struct TodoView: View {
    @StateObject private var viewModel = TodoViewModel()
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerView
                
                ScrollView {
                    LazyVStack(spacing: 24) {
                        todoSection(title: "Due This Week", items: viewModel.dueThisWeek)
                        todoSection(title: "Missing", items: viewModel.missing)
                        todoSection(title: "Due Later", items: viewModel.dueLater)
                    }
                    .padding()
                }
            }
            .padding(.top, 16)
            .background(
                VStack(spacing: 0) {
                    Color.Tally.navyBackground
                        .frame(height: 120)
                    Color.Tally.lightGrayBg
                }
                .ignoresSafeArea()
            )
            .toolbar(.hidden, for: .navigationBar)
        }
    }
    
    private var headerView: some View {
        HStack {
            Button(action: {}) {
                HStack {
                    Text("Sorted by Due Date")
                        .font(.Tally.title2)
                        .foregroundColor(Color.Tally.cardBackground)
                    Image(systemName: "chevron.down")
                        .foregroundColor(Color.Tally.cardBackground)
                }
            }
            Spacer()
            Button(action: {}) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.title2)
                    .foregroundColor(Color.Tally.cardBackground)
            }
        }
        .padding(.horizontal)
        .padding(.top, 20)
        .padding(.bottom, 20)
    }
    
    private func todoSection(title: String, items: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.Tally.title2)
                .foregroundColor(Color.Tally.textPrimary)
            
            LazyVStack(spacing: 12) {
                ForEach(items) { item in
                    HStack(spacing: 16) {
                        Circle()
                            .fill(item.color)
                            .frame(width: 12, height: 12)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.taskName)
                                .font(.Tally.headline)
                                .foregroundColor(Color.Tally.textPrimary)
                            Text(item.courseName)
                                .font(.Tally.caption)
                                .foregroundColor(Color.Tally.textSecondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(item.dueDate)
                                .font(.Tally.caption)
                                .foregroundColor(Color.Tally.textSecondary)
                            Image(systemName: "chevron.right")
                                .foregroundColor(Color.Tally.textSecondary)
                                .font(.caption)
                        }
                    }
                    .tallyCardStyle()
                }
            }
        }
    }
}


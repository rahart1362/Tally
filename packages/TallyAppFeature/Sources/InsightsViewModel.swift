import Foundation
import SwiftUI

@MainActor
public class InsightsViewModel: ObservableObject {
    @Published public var isLoading: Bool = false
    
    @Published public var studyStreakDays: Int = 12
    @Published public var gpaTrend: Double = 3.8
    @Published public var trendDirection: String = "+0.2"
    
    // Category Breakdown
    @Published public var assignmentsPercentage: Double = 40.0
    @Published public var examsPercentage: Double = 30.0
    @Published public var quizzesPercentage: Double = 20.0
    @Published public var discussionsPercentage: Double = 10.0
    
    // Risk & Workload
    @Published public var atRiskCourses: [String] = ["Calculus II (Borderline C+)"]
    @Published public var heavyWorkloadWeeks: [String] = ["Next Week (Oct 12-18): 4 Exams, 2 Papers"]
    
    // GPAs over time for chart
    @Published public var termGPAs: [Double] = [3.2, 3.4, 3.5, 3.8]
    
    public init() {
        loadData()
    }
    
    public func loadData() {
        self.isLoading = true
        // Simulate network fetch
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.isLoading = false
        }
    }
}


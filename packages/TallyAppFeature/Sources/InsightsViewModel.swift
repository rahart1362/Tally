import Foundation
import SwiftUI

@MainActor
public class InsightsViewModel: ObservableObject {
    @Published public var isLoading: Bool = false
    
    @Published public var studyStreakDays: Int = 12
    @Published public var assignmentsPercentage: Double = 40.0
    @Published public var examsPercentage: Double = 30.0
    @Published public var quizzesPercentage: Double = 20.0
    @Published public var discussionsPercentage: Double = 10.0
    
    public init() {
        loadData()
    }
    
    public func loadData() {
        self.isLoading = true
        self.isLoading = false
    }
}


import Foundation
import SwiftUI
import TallyDesignSystem

public struct AssignmentItem: Identifiable {
    public let id = UUID()
    public let title: String
    public let date: String
    public let scoreText: String
    public let isGoodScore: Bool
}

@MainActor
public class CourseDetailViewModel: ObservableObject {
    @Published public var isLoading: Bool = false
    
    @Published public var assignments: [AssignmentItem] = [
        AssignmentItem(title: "Problem Set 3", date: "Oct 10", scoreText: "95/100", isGoodScore: true),
        AssignmentItem(title: "Midterm Exam", date: "Oct 1", scoreText: "88/100", isGoodScore: true),
        AssignmentItem(title: "Reading Quiz 2", date: "Sep 25", scoreText: "7/10", isGoodScore: false)
    ]
    
    public init() {
        loadData()
    }
    
    public func loadData() {
        self.isLoading = true
        // mock loading
        self.isLoading = false
    }
}


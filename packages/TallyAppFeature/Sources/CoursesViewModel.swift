import Foundation
import SwiftUI
import TallyDesignSystem

public struct CourseItem: Identifiable {
    public let id = UUID()
    public let name: String
    public let code: String
    public let icon: String
    public let color: Color
    public let gradeLetter: String
    public let percentage: Double
    public let nextAssignment: String
    public let dueDate: String
}

@MainActor
public class CoursesViewModel: ObservableObject {
    @Published public var isLoading: Bool = false
    @Published public var term: String = "Spring 2024"
    
    @Published public var courses: [CourseItem] = [
        CourseItem(name: "Calculus II", code: "MATH 102", icon: "function", color: Color.Tally.calculusBlue, gradeLetter: "A-", percentage: 90.1, nextAssignment: "Problem Set 4", dueDate: "Tomorrow"),
        CourseItem(name: "Intro to Psychology", code: "PSYC 101", icon: "brain.head.profile", color: Color.Tally.psychologyGreen, gradeLetter: "B+", percentage: 87.2, nextAssignment: "Reading Quiz", dueDate: "Oct 15"),
        CourseItem(name: "Biology 101", code: "BIOL 101", icon: "leaf", color: Color.Tally.biologyPurple, gradeLetter: "A", percentage: 93.4, nextAssignment: "Lab Report", dueDate: "Oct 18"),
        CourseItem(name: "World History", code: "HIST 201", icon: "globe", color: Color.Tally.historyOrange, gradeLetter: "B", percentage: 82.0, nextAssignment: "Essay Draft", dueDate: "Oct 20"),
        CourseItem(name: "English Composition", code: "ENGL 101", icon: "book", color: Color.Tally.englishBlue, gradeLetter: "A-", percentage: 89.0, nextAssignment: "Peer Review", dueDate: "Oct 22")
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


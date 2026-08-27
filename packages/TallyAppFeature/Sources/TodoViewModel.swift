import Foundation
import SwiftUI
import TallyDesignSystem

public struct TodoItem: Identifiable {
    public let id = UUID()
    public let taskName: String
    public let courseName: String
    public let dueDate: String
    public let color: Color
}

@MainActor
public class TodoViewModel: ObservableObject {
    @Published public var isLoading: Bool = false
    
    @Published public var dueThisWeek: [TodoItem] = [
        TodoItem(taskName: "Problem Set 4", courseName: "Calculus II", dueDate: "Tomorrow, 11:59 PM", color: Color.Tally.calculusBlue),
        TodoItem(taskName: "Lab Report", courseName: "Biology 101", dueDate: "Friday, 5:00 PM", color: Color.Tally.biologyPurple)
    ]
    
    @Published public var missing: [TodoItem] = [
        TodoItem(taskName: "Week 3 Quiz", courseName: "Psychology 101", dueDate: "Past Due", color: Color.Tally.psychologyGreen)
    ]
    
    @Published public var dueLater: [TodoItem] = [
        TodoItem(taskName: "Essay Draft", courseName: "World History", dueDate: "Oct 20, 11:59 PM", color: Color.Tally.historyOrange),
        TodoItem(taskName: "Peer Review", courseName: "English Composition", dueDate: "Oct 22, 11:59 PM", color: Color.Tally.englishBlue)
    ]
    
    public init() {
        loadData()
    }
    
    public func loadData() {
        self.isLoading = true
        self.isLoading = false
    }
}


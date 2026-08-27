import Foundation
import SwiftUI
import TallyDesignSystem

public struct AlertItem: Identifiable {
    public let id = UUID()
    public let type: AlertType
    public let count: Int
    public let title: String
    public let subtitle: String
    
    public enum AlertType {
        case missing, upcoming, updated
        var color: Color {
            switch self {
            case .missing: return Color.Tally.alertRed
            case .upcoming: return Color.Tally.psychologyGreen
            case .updated: return Color.Tally.calculusBlue
            }
        }
    }
}

public struct ScheduleItem: Identifiable {
    public let id = UUID()
    public let time: String
    public let courseName: String
    public let type: String
    public let location: String
    public let color: Color
}

@MainActor
public class DashboardViewModel: ObservableObject {
    @Published public var isLoading: Bool = false
    
    @Published public var overallGradePercentage: Double = 87.2
    @Published public var overallGradeLetter: String = "B+"
    @Published public var trend: Double = 5.2
    
    @Published public var alerts: [AlertItem] = [
        AlertItem(type: .missing, count: 2, title: "Missing Assignments", subtitle: "Calculus, World History"),
        AlertItem(type: .upcoming, count: 1, title: "Upcoming Exam", subtitle: "Biology 101 - Tomorrow"),
        AlertItem(type: .updated, count: 1, title: "Grade Updated", subtitle: "Intro to Psychology")
    ]
    
    @Published public var schedule: [ScheduleItem] = [
        ScheduleItem(time: "9:00 AM", courseName: "Calculus II", type: "Lecture", location: "Room 304", color: Color.Tally.calculusBlue),
        ScheduleItem(time: "11:00 AM", courseName: "Intro to Psychology", type: "Discussion", location: "Hall B", color: Color.Tally.psychologyGreen),
        ScheduleItem(time: "2:00 PM", courseName: "World History", type: "Lecture", location: "Room 101", color: Color.Tally.historyOrange)
    ]
    
    public init() {
        loadData()
    }
    
    public func loadData() {
        self.isLoading = true
        // Mock data loaded
        self.isLoading = false
    }
}


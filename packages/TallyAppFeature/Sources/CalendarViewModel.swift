import Foundation
import SwiftUI
import TallyDesignSystem

public struct CalendarEventItem: Identifiable {
    public let id = UUID()
    public let courseName: String
    public let type: String
    public let location: String
    public let color: Color
    public let startHour: Double
    public let durationHours: Double
}

@MainActor
public class CalendarViewModel: ObservableObject {
    @Published public var isLoading: Bool = false
    @Published public var monthYear: String = "October 2024"
    
    @Published public var events: [CalendarEventItem] = [
        CalendarEventItem(courseName: "Calculus II", type: "Lecture", location: "Room 304", color: Color.Tally.calculusBlue, startHour: 9.0, durationHours: 1.5),
        CalendarEventItem(courseName: "Intro to Psychology", type: "Discussion", location: "Hall B", color: Color.Tally.psychologyGreen, startHour: 11.0, durationHours: 1.0),
        CalendarEventItem(courseName: "World History", type: "Lecture", location: "Room 101", color: Color.Tally.historyOrange, startHour: 14.0, durationHours: 1.5)
    ]
    
    public init() {
        loadData()
    }
    
    public func loadData() {
        self.isLoading = true
        self.isLoading = false
    }
}


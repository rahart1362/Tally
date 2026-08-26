import SwiftUI

public struct MainTabView: View {
    public init() {}
    public var body: some View {
        TabView {
            DashboardView().tabItem { Label("Dashboard", systemImage: "house") }
            CoursesView().tabItem { Label("Courses", systemImage: "books.vertical") }
            CalendarView().tabItem { Label("Calendar", systemImage: "calendar") }
            TodoView().tabItem { Label("To-Do", systemImage: "checklist") }
            InsightsView().tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }
        }
    }
}

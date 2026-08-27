import SwiftUI
import TallyDesignSystem

public struct MainTabView: View {
    public init() {}
    
    public var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Image(systemName: "house")
                    Text("Dashboard")
                }
            
            CoursesView()
                .tabItem {
                    Image(systemName: "book.closed")
                    Text("Courses")
                }
            
            CalendarView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Calendar")
                }
            
            TodoView()
                .tabItem {
                    Image(systemName: "checklist")
                    Text("To Do")
                }
            
            InsightsView()
                .tabItem {
                    Image(systemName: "ellipsis.circle")
                    Text("More")
                }
        }
        .accentColor(Color.Tally.navyBackground)
    }
}

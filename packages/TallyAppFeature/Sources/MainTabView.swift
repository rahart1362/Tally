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
        .tint(Color.Tally.navyBackground)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

import Foundation
import BackgroundTasks
import TallyCache

public final class BackgroundSyncManager {
    public static let shared = BackgroundSyncManager()
    public let refreshTaskIdentifier = "com.tally.app.refresh"
    
    private init() {}
    
    /// Registers the background task. Must be called early in app lifecycle (e.g., init of App struct).
    public func registerTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskIdentifier, using: nil) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else { return }
            self.handleAppRefresh(task: appRefreshTask)
        }
    }
    
    /// Schedules the next background refresh aiming for 2x daily (e.g., closest 8 AM or 8 PM),
    /// but ensuring at least 6 hours have passed to prevent battery drain.
    public func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        
        let now = Date()
        let calendar = Calendar.current
        
        // Find next 8 AM or 8 PM
        var next8AM = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now)!
        var next8PM = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now)!
        
        if next8AM < now {
            next8AM = calendar.date(byAdding: .day, value: 1, to: next8AM)!
        }
        if next8PM < now {
            next8PM = calendar.date(byAdding: .day, value: 1, to: next8PM)!
        }
        
        // Pick the closest target time
        var targetDate = min(next8AM, next8PM)
        
        // Ensure the target is at least 6 hours away to prevent excessive refreshes
        let sixHoursFromNow = now.addingTimeInterval(6 * 60 * 60)
        if targetDate < sixHoursFromNow {
            targetDate = sixHoursFromNow
        }
        
        request.earliestBeginDate = targetDate
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Scheduled next background refresh for: \(targetDate)")
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
    
    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Reschedule the next task right away
        scheduleNextRefresh()
        
        let operation = Task {
            await RefreshOrchestrator.shared.refreshAll()
            task.setTaskCompleted(success: true)
        }
        
        task.expirationHandler = {
            operation.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}

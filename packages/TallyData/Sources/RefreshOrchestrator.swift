import Foundation
import TallyCache
import TallyNotifications
import TallyCalendarSync

public class RefreshOrchestrator: ObservableObject {
    public static let shared = RefreshOrchestrator()
    
    @Published public var isRefreshing = false
    @Published public var isShowingStaleData = false
    @Published public var lastRefreshed: Date? = nil
    
    private let timeoutInterval: TimeInterval = 10.0
    
    public init() {}
    
    /// Simulates a background pull from Canvas, saving data to the cache,
    /// and triggering local notifications/calendar sync.
    public func refreshAll() async {
        await MainActor.run {
            self.isRefreshing = true
            self.isShowingStaleData = false
        }
        
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeoutInterval * 1_000_000_000))
            if !Task.isCancelled {
                await MainActor.run { [weak self] in
                    if self?.isRefreshing == true {
                        self?.isShowingStaleData = true
                    }
                }
            }
        }
        
        do {
            // Simulate network delay
            try await Task.sleep(nanoseconds: 1_500_000_000)
            
            // In a real app, this would call CanvasAPIClient and decode DTOs.
            // For now, we simulate success and update the sync integrations.
            
            // Sync calendar event (simulated)
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            CalendarSyncManager.shared.syncEvent(
                id: "simulated_event_1",
                title: "Calculus III Midterm",
                startDate: tomorrow,
                endDate: tomorrow.addingTimeInterval(3600),
                notes: "Synced from Canvas"
            )
            
            // Schedule a reminder notification for 1 hour before the exam
            NotificationManager.shared.scheduleReminder(
                id: "simulated_exam_alert",
                title: "Upcoming Exam",
                body: "Your Calculus III Midterm is in 1 hour.",
                date: tomorrow.addingTimeInterval(-3600)
            )
            
            timeoutTask.cancel()
            
            await MainActor.run { [weak self] in
                self?.isRefreshing = false
                self?.isShowingStaleData = false
                self?.lastRefreshed = Date()
            }
        } catch {
            timeoutTask.cancel()
            await MainActor.run { [weak self] in
                self?.isRefreshing = false
                self?.isShowingStaleData = true
            }
        }
    }
}

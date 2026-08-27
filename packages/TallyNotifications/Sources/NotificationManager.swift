import Foundation
import UserNotifications
import TallyDomain

/// Manages local push notifications for reminders and alerts.
public final class NotificationManager {
    public static let shared = NotificationManager()
    
    private init() {}
    
    /// Request user permission to send local notifications.
    public func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization error: \(error.localizedDescription)")
            } else {
                print("Notification permission granted: \(granted)")
            }
        }
    }
    
    /// Schedule a local reminder for a specific due date.
    /// - Parameters:
    ///   - id: Unique identifier for the notification (usually the assignment ID).
    ///   - title: Notification title.
    ///   - body: Notification body text.
    ///   - date: The date and time the notification should fire.
    public func scheduleReminder(id: String, title: String, body: String, date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        // Create a calendar trigger
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error.localizedDescription)")
            }
        }
    }
    
    /// Remove scheduled notifications for specific IDs (e.g., if an assignment is completed).
    public func cancelReminders(for ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
    
    /// Clear all pending notifications.
    public func cancelAllReminders() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

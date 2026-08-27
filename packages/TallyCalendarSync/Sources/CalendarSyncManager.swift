import Foundation
import EventKit
import TallyDomain

/// Manages syncing Tally assignments and schedules to Apple Calendar (EventKit).
public final class CalendarSyncManager {
    public static let shared = CalendarSyncManager()
    
    private let eventStore = EKEventStore()
    private let tallyCalendarTitle = "Tally Academic"
    
    private init() {}
    
    /// Requests access to Apple Calendar.
    public func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                return try await eventStore.requestWriteOnlyAccessToEvents()
            } else {
                return try await eventStore.requestAccess(to: .event)
            }
        } catch {
            print("Failed to request calendar access: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Gets or creates a dedicated "Tally Academic" calendar.
    private func getTallyCalendar() -> EKCalendar? {
        let calendars = eventStore.calendars(for: .event)
        if let existing = calendars.first(where: { $0.title == tallyCalendarTitle }) {
            return existing
        }
        
        let newCalendar = EKCalendar(for: .event, eventStore: eventStore)
        newCalendar.title = tallyCalendarTitle
        newCalendar.source = eventStore.defaultCalendarForNewEvents?.source
        
        do {
            try eventStore.saveCalendar(newCalendar, commit: true)
            return newCalendar
        } catch {
            print("Failed to create Tally calendar: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Syncs an assignment to the calendar.
    public func syncEvent(id: String, title: String, startDate: Date, endDate: Date, notes: String?) {
        guard let calendar = getTallyCalendar() else { return }
        
        // In a full implementation, we'd query for existing events by ID and update them.
        // For simplicity in this demo, we just create a new one.
        
        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        
        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            print("Successfully synced event to Apple Calendar: \(title)")
        } catch {
            print("Failed to save event: \(error.localizedDescription)")
        }
    }
}

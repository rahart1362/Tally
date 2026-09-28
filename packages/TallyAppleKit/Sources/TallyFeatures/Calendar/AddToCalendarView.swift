import EventKit
import EventKitUI
import SwiftUI
import TallyDomain

/// PMO R6: per-item "Add to Calendar" through the system's event editor, pre-filled. Since iOS 17,
/// `EKEventEditViewController` runs out of process and needs no calendar access, so Tally asks for
/// none: there is no permission prompt, and Tally never reads the student's calendars (Apple,
/// "Accessing the event store"; ux-ui.md §3.2 stage 6). The student chooses whether to add it.
struct AddToCalendarView: UIViewControllerRepresentable {
    let draft: CalendarEventDraft
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        // Creating a store and an unsaved event asks for nothing; the editor saves, if the student
        // taps Add, in its own process.
        let store = EKEventStore()
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = Self.event(for: draft, in: store)
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    /// The unsaved event the editor opens with: the draft's title, times, place and link. Tested
    /// in a hosted test rather than through the system sheet.
    static func event(for draft: CalendarEventDraft, in store: EKEventStore) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.isAllDay
        event.location = draft.location
        return event
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        /// Explicit and nonisolated (plan 06 A2; swiftlang/swift#88036): no isolated deinit.
        nonisolated deinit {}

        /// UIKit calls this on the main thread when the student taps Add or Cancel. `nonisolated`
        /// so it satisfies the protocol whatever the SDK's annotation, then asserts the main actor.
        nonisolated func eventEditViewController(
            _ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction
        ) {
            MainActor.assumeIsolated {
                onFinish()
            }
        }
    }
}

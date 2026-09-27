import SwiftUI

/// A one-line wrapper around SwiftUI's `AccessibilityNotification.Announcement`
/// (ux-ui.md §3.2 stage 5 / §3.7.9: "VoiceOver gets an
/// `AccessibilityNotification.Announcement` per phase"), so
/// `FirstSyncViewModel.swift` doesn't need to import SwiftUI just to speak
/// one string.
enum AccessibilityAnnouncer {
    static func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }
}

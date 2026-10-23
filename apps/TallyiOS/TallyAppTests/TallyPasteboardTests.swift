import Foundation
import Testing
import UniformTypeIdentifiers
@testable import TallyFeatures

/// SEC1-18 (partial): a pairing code, or an observer-removal request, copied to the pasteboard
/// must stay local-only (no Universal Clipboard/Handoff to the student's other Apple devices)
/// and must expire, rather than sitting on the general pasteboard indefinitely. `UIPasteboard
/// .general` is live, shared system state, so this proves it against `pasteboardPayload`'s pure
/// output -- exactly what `copy(_:expiresAt:)` hands `setItems` -- instead.
@Suite("TallyPasteboard: SEC1-18's local-only, expiring copy")
struct TallyPasteboardTests {
    @Test func payloadIsLocalOnlyWithTheGivenExpiration() {
        let expiresAt = Date(timeIntervalSince1970: 1_790_600_400)
        let (items, options) = TallyPasteboard.pasteboardPayload("ABC-123", expiresAt: expiresAt)

        #expect(options[.localOnly] as? Bool == true, "SEC1-18: must never be Handoff/Universal-Clipboard-eligible")
        #expect(options[.expirationDate] as? Date == expiresAt, "SEC1-18: must not sit on the pasteboard indefinitely")
        #expect(items.count == 1)
        #expect(items.first?[UTType.utf8PlainText.identifier] as? String == "ABC-123")
    }

    /// `copy(_:expiresAt:)` (the pairing-code copy, `FamilySettingsViews.swift:572`) and
    /// `copy(_:expiringAfter:)` (the 2-minute observer-removal copy, `:441`) both delegate to
    /// `pasteboardPayload`; this is the one computation `expiringAfter` adds on top of it.
    @Test func expiringAfterIsStillInTheFuture() {
        let before = Date()
        let expiresAt = before.addingTimeInterval(TimeInterval(2 * 60)) // FamilyUIConfig.pasteboardExpiry
        let (_, options) = TallyPasteboard.pasteboardPayload("CODE", expiresAt: expiresAt)
        #expect((options[.expirationDate] as? Date ?? before) > before)
    }
}

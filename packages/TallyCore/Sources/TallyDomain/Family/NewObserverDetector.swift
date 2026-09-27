import Foundation

/// One newly detected observer (family-linking.md §4.2 "New-observer alert (security
/// control)", §6.7 "Leaked pairing code"). Carries no name — kit hard rule 3 / R10 — since
/// the alert and its optional notification both read "A new observer was linked to your
/// Canvas account," never who; a name would need the caller's own sealed lookup anyway.
public struct NewObserverAlert: Sendable, Equatable {
    public let observerCanvasUserID: String
    public init(observerCanvasUserID: String) { self.observerCanvasUserID = observerCanvasUserID }
}

/// Detects a change in who observes this student's Canvas account, from one refresh's S1
/// result (`GET /users/self/observers`) to the next (family-linking.md §4.2, FAM-07).
/// Catches a leaked pairing code or an unexpected link — not a removal, which is either the
/// school's own action or simply nothing alarming.
public enum NewObserverDetector {
    /// - Parameters:
    ///   - currentObserverIDs: this refresh's observer ids, in whatever order S1 returned.
    ///   - previouslySeenObserverIDs: the set this student's account last saw, or `nil` on
    ///     the very first refresh after sign-in — there is no previous set to compare
    ///     against yet, so nothing fires (family-linking.md §4.2 "the first refresh after
    ///     sign-in only seeds the set, so it never fires then").
    /// - Returns: exactly one alert per id present in `currentObserverIDs` but absent from
    ///   `previouslySeenObserverIDs`, in `currentObserverIDs`'s own order. An id that
    ///   disappeared yields no alert at all.
    public static func detect(currentObserverIDs: [String], previouslySeenObserverIDs: Set<String>?) -> [NewObserverAlert] {
        guard let previouslySeenObserverIDs else { return [] }
        return currentObserverIDs
            .filter { !previouslySeenObserverIDs.contains($0) }
            .map(NewObserverAlert.init)
    }
}

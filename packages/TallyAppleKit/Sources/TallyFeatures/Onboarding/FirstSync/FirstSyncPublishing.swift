import TallyDomain
import TallyStrings

/// The four phases of a first sync (ux-ui.md §3.2 stage 5: "Phases come
/// from the refresh coordinator: profile+courses → grades → assignments/due
/// → calendar"), in the order they complete.
public nonisolated enum FirstSyncPhase: Sendable, Equatable, CaseIterable {
    case profileAndCourses
    case grades
    case dueItems
    case calendar

    /// One VoiceOver announcement per phase (ux-ui.md §3.7.9 rules:
    /// "VoiceOver gets an `AccessibilityNotification.Announcement` per phase").
    var announcementText: String {
        switch self {
        case .profileAndCourses: String(localized: L10n.Onboarding.FirstSync.announceCourses())
        case .grades: String(localized: L10n.Onboarding.FirstSync.announceGrades())
        case .dueItems: String(localized: L10n.Onboarding.FirstSync.announceDueDates())
        case .calendar: String(localized: L10n.Onboarding.FirstSync.announceCalendar())
        }
    }
}

/// What the (future) `RefreshCoordinator` reports during a first sync. A
/// closed, Linux-shaped vocabulary — `FirstSyncViewModel` never sees raw
/// Canvas data, only progress.
public nonisolated enum FirstSyncEvent: Sendable, Equatable {
    case phaseCompleted(FirstSyncPhase)
    case finished
    /// Total failure with nothing saved yet (ux-ui.md §3.2 stage 5: "On
    /// total failure, show the §3.2.3 error with nothing saved").
    case failed(RefreshFailure)
}

/// The port `FirstSyncViewModel` depends on. "A progressive skeleton view
/// model driven by a protocol that publishes phase events" (this work
/// package's brief). The real conformance is `CoordinatorFirstSyncPublisher`,
/// over the new account's `RefreshCoordinator` (plan 06 step 9).
/// `nonisolated` (like the phase and event types): the publisher runs off the main actor.
public nonisolated protocol FirstSyncPublishing: Sendable {
    func events() -> AsyncStream<FirstSyncEvent>
}

/// The default until the app-core team's `RefreshCoordinator` is wired in.
/// Reports a prompt, honest failure rather than fabricating progress or
/// hanging forever — the same seam pattern as `UnavailableInstitutionSearch`
/// (UX-WP-08) and `UnavailableTokenExchange`/`UnavailableWebAuthPresenter`
/// (UX-WP-09).
public nonisolated struct UnavailableFirstSyncPublisher: FirstSyncPublishing {
    public init() {}
    public func events() -> AsyncStream<FirstSyncEvent> {
        AsyncStream { continuation in
            continuation.yield(.failed(.unknown))
            continuation.finish()
        }
    }
}

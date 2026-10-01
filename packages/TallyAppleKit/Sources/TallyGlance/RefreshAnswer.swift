import Foundation
import TallyDomain

/// What "Refresh Tally" (Siri, Shortcuts, the Control Center control) says after it ran
/// (integrations.md §2.4: "'Updated' or 'Open Tally to sign in'… it says so honestly"), from the
/// account's freshness once the refresh returned (`RefreshCoordinator.run`), or `nil` when there
/// was no account to refresh from where the intent ran: signed out, exploring sample data (which
/// never refreshes, ASC-14), or the app launched only to run the intent before its account
/// attached. Pure, so the mapping is tested on every state.
public enum RefreshAnswer: Equatable, Sendable {
    case updated
    case stillRefreshing
    case offline(showing: Date?)
    case signInExpired
    case failed(showing: Date?)
    case openTally

    public init(state: FreshnessState?) {
        switch state {
        case .fresh?: self = .updated
        case .refreshing?, .delayed?: self = .stillRefreshing
        case .offline(let showing)?: self = .offline(showing: showing)
        case .authExpired?: self = .signInExpired
        case .failed(_, let showing)?: self = .failed(showing: showing)
        case .noCache?, nil: self = .openTally
        }
    }
}

import Foundation

/// PAY-05: what the paywall says, decided from plain values; the app words each part
/// (`L10n.Subscription`). **No price is here:** the App Store formats every price
/// (`Product.displayPrice`), and the app shows that text as it is.
///
/// Plan 08 G-6: for a school whose grades are not in Canvas (`SchoolGradeSummary.noneInCanvas`),
/// the paywall makes **no grade, what-if or grade-alert claim**. Due dates, reminders, the calendar
/// and the workload keep their value, so they are what it offers.
public struct PaywallContent: Sendable, Equatable {
    /// One line of "what's included", in display order.
    public enum Feature: String, Sendable, Equatable, CaseIterable {
        /// Grades and what-if for every course (a grade claim).
        case grades
        /// Due dates, To-Do and the calendar, kept up to date.
        case dueDates
        /// Reminders before work is due.
        case reminders
        /// Insights, widgets and Shortcuts.
        case insights
        /// Workload insights, widgets and Shortcuts (no grade trends: the G-6 wording).
        case workload
        /// Everything stays on this iPhone.
        case privacy

        /// Whether the line promises grades (G-6 forbids it for `.noneInCanvas` schools).
        public var claimsGrades: Bool {
            switch self {
            case .grades, .insights: true
            case .dueDates, .reminders, .workload, .privacy: false
            }
        }
    }

    public enum Variant: String, Sendable, Equatable, CaseIterable {
        case standard
        /// G-6: for a school that keeps its grades outside Canvas.
        case noGradeClaims
    }

    /// The purchase button's words: a free trial when this Apple Account is eligible for one.
    public enum Action: String, Sendable, Equatable, CaseIterable {
        case startFreeTrial
        case subscribe
    }

    public let variant: Variant
    public let features: [Feature]
    public let action: Action
    /// "<trial> free, then <price>/<period>": only when the App Store says this Apple Account is
    /// eligible for the introductory offer.
    public let showsTrial: Bool

    public init(school: SchoolGradeSummary, isEligibleForTrial: Bool) {
        variant = school == .noneInCanvas ? .noGradeClaims : .standard
        switch variant {
        case .standard: features = [.grades, .dueDates, .reminders, .insights, .privacy]
        case .noGradeClaims: features = [.dueDates, .reminders, .workload, .privacy]
        }
        showsTrial = isEligibleForTrial
        action = isEligibleForTrial ? .startFreeTrial : .subscribe
    }
}

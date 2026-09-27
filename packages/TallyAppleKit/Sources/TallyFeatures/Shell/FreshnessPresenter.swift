import Foundation
import TallyDomain

/// UX-WP-06: a pure presenter mapping `FreshnessState` (TallyDomain) to kit-11 copy
/// (ux-ui.md §3.3's table). Every case is a plain function of its inputs — no I/O, no clock
/// reads — so every state is unit-testable with a fixed `now`.
/// `nonisolated`: `TallyFeatures` defaults to `MainActor` isolation (Package.swift), but this
/// presenter is a pure function with no UI/main-thread dependency — marking it explicitly lets it
/// (and its tests) be called synchronously from any context.
public nonisolated enum FreshnessPresenter {
    public nonisolated enum Symbol: Sendable, Equatable {
        case checkmarkCircle, clock, spinner, clockBadgeExclamation, wifiSlash, exclamationTriangle, personBadgeExclamation
    }

    public nonisolated enum Action: Sendable, Equatable {
        case refresh, retry, signIn, none
    }

    /// `longText` is the global breadcrumb copy; `nil` whenever `state.showsStaleBreadcrumb`
    /// is `false` (ux-ui.md §3.3: "shown only in delayed, offline, failed and authExpired", and
    /// only once there is saved data to describe — `FreshnessState.showing != nil`).
    public nonisolated struct Presentation: Sendable, Equatable {
        public let shortText: String
        public let longText: String?
        public let symbol: Symbol
        public let action: Action
        public var showsBreadcrumb: Bool { longText != nil }
    }

    public static func present(
        _ state: FreshnessState, now: Date, locale: Locale = Locale(identifier: "en_US"), timeZone: TimeZone = .current
    ) -> Presentation {
        switch state {
        case .noCache:
            // Not in ux-ui.md §3.3's table (that table starts at "fresh"): before any successful
            // sync the app shows the first-sync skeleton, not this footer. Included here only so
            // the presenter is total; UNVERIFIED against the UX doc.
            return Presentation(shortText: "Not refreshed yet", longText: nil, symbol: .clock, action: .refresh)

        case .fresh(let at):
            let justNow = now.timeIntervalSince(at) < 60
            return Presentation(shortText: justNow ? "Updated just now" : "Updated \(when(at, now: now, locale: locale, timeZone: timeZone))",
                                longText: nil, symbol: justNow ? .checkmarkCircle : .clock, action: .refresh)

        case .refreshing(let showing):
            let base = showing.map { "Updated \(when($0, now: now, locale: locale, timeZone: timeZone))" } ?? "Refreshing"
            return Presentation(shortText: "\(base) · Refreshing…", longText: nil, symbol: .spinner, action: .none)

        case .delayed(let showing):
            guard let showing else {
                // "showing == nil means the first sync is slow: there is no cache yet, so no
                // stale breadcrumb" (FreshnessState doc comment).
                return Presentation(shortText: "First sync is taking longer than expected", longText: nil,
                                    symbol: .clockBadgeExclamation, action: .retry)
            }
            let saved = when(showing, now: now, locale: locale, timeZone: timeZone)
            return Presentation(shortText: "Saved \(saved)",
                                longText: "Live refresh is taking longer than expected — showing saved data from \(saved).",
                                symbol: .clockBadgeExclamation, action: .retry)

        case .offline(let showing):
            guard let showing else {
                return Presentation(shortText: "No saved data — you're offline", longText: nil, symbol: .wifiSlash, action: .none)
            }
            let saved = when(showing, now: now, locale: locale, timeZone: timeZone)
            return Presentation(shortText: "Saved \(saved)", longText: "You're offline — showing your latest saved data.",
                                symbol: .wifiSlash, action: .none)

        case .authExpired(let showing):
            guard let showing else {
                return Presentation(shortText: "Sign-in expired", longText: nil, symbol: .personBadgeExclamation, action: .signIn)
            }
            let saved = when(showing, now: now, locale: locale, timeZone: timeZone)
            return Presentation(shortText: "Saved \(saved)",
                                longText: "Your sign-in expired — showing saved data from \(saved).",
                                symbol: .personBadgeExclamation, action: .signIn)

        case .failed(_, let showing):
            guard let showing else {
                return Presentation(shortText: "Couldn't refresh yet", longText: nil, symbol: .exclamationTriangle, action: .retry)
            }
            let saved = when(showing, now: now, locale: locale, timeZone: timeZone)
            return Presentation(shortText: "Saved \(saved)", longText: "Couldn't refresh — showing saved data from \(saved).",
                                symbol: .exclamationTriangle, action: .retry)
        }
    }

    /// "2:14 PM" today; "Tue 2:14 PM" within the last 6 days; "Sep 12" otherwise
    /// (ux-ui.md §3.3's three examples).
    private static func when(_ date: Date, now: Date, locale: Locale, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: timeZone))
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days >= 0, days < 7 {
            return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
                .weekday(.abbreviated).time(.shortened))
        }
        return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: timeZone)
            .month(.abbreviated).day())
    }
}
